import SwiftUI
import CoreBluetooth
import WatchConnectivity
import Combine


class AdvancedBLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate, WCSessionDelegate {
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectedPeripheral: CBPeripheral? = nil
    @Published var isConnected = false
    
    // Core Parameters
    @Published var homeScore = 0
    @Published var awayScore = 0
    @Published var period = 1
    @Published var totalPeriods = 4
    @Published var brightness: Double = 40.0
    @Published var timerMin = 10
    @Published var timerSec = 0
    @Published var isTimerRunning = false
    @Published var homeName = String(localized: "HOME")
    @Published var awayName = String(localized: "AWAY")
    @Published var periodLabelText = String(localized: "Period")
    @Published var renameStatus = ""
    
    // Board telemetry (notification on the main characteristic)
    @Published var batteryPercent: Int? = nil
    @Published var boardProtocolVersion: Int? = nil
    @Published var telemetryReceived = false
    /// Telemetry layout version this app expects. Keep in sync with PROTOCOL_VERSION in scoreboard_BT_ESP32S3.ino.
    static let expectedProtocolVersion = 2
    var boardFirmwareOutdated: Bool { telemetryReceived && (boardProtocolVersion ?? 1) < Self.expectedProtocolVersion }
    
    // Visual Banner Alert State publishers
    @Published var alertBannerTitle = ""
    @Published var showAlertBanner = false
    
    private var centralManager: CBCentralManager!
    private var targetCharacteristic: CBCharacteristic?
    private var configCharacteristic: CBCharacteristic?
    private var nativeClockTimer: Timer? = nil
    private var wasIntentionalDisconnect = false
    
    let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789012")
    let charUUID    = CBUUID(string: "87654321-4321-4321-4321-210987654321")
    // CONFIG characteristic: [cmd, args...] writes, [cmd, status] notifications (status 0 = OK).
    // Keep in sync with scoreboard_BT_ESP32S3.ino.
    let configUUID  = CBUUID(string: "87654321-4321-4321-4321-210987654322")
    private let cmdSetName: UInt8 = 0x01
    private let cmdApply: UInt8 = 0x02
    static let deviceNameMaxLength = 20
    
    override init() {
        super.init()
        let savedMinutes = UserDefaults.standard.integer(forKey: "lastSavedMinutes")
        if savedMinutes > 0 { timerMin = savedMinutes }
        centralManager = CBCentralManager(delegate: self, queue: nil)
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func toggleClock() {
        isTimerRunning.toggle()
        if isTimerRunning {
            triggerHapticAlert(type: .startEvent)
            nativeClockTimer?.invalidate()
            nativeClockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.handleClockTick()
            }
        } else {
            nativeClockTimer?.invalidate()
            nativeClockTimer = nil
        }
        syncDataToDisplay()
    }
    
    private func handleClockTick() {
        if timerSec > 0 {
            timerSec -= 1
        } else {
            if timerMin > 0 {
                timerMin -= 1
                timerSec = 59
            } else {
                nativeClockTimer?.invalidate()
                nativeClockTimer = nil
                isTimerRunning = false
                timerSec = 0
                
                if period < totalPeriods {
                    period += 1
                    let savedMinutes = UserDefaults.standard.integer(forKey: "lastSavedMinutes")
                    timerMin = savedMinutes > 0 ? savedMinutes : 10
                    triggerHapticAlert(type: .periodAdvance)
                } else {
                    triggerHapticAlert(type: .matchComplete)
                }
            }
        }
        syncDataToDisplay()
    }
    
    func resetClockManual(minutes: Int) {
        nativeClockTimer?.invalidate()
        nativeClockTimer = nil
        isTimerRunning = false
        timerMin = minutes
        timerSec = 0
        syncDataToDisplay()
    }
    
    /// The LED panel font is ASCII-only, so strip accents and drop anything else (e.g. "1.º Período" -> "1. Periodo").
    /// Also removes "|", which separates the fields of the text payload.
    private func panelSafe(_ text: String) -> String {
        let folded = text.folding(options: .diacriticInsensitive, locale: .current)
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter { $0.isASCII && $0 != "|" }))
    }
    
    func syncDataToDisplay() {
        guard let peripheral = connectedPeripheral, let characteristic = targetCharacteristic else { return }
        
        var packet = Data([
            UInt8(homeScore),
            UInt8(awayScore),
            UInt8(period),
            UInt8(Int(brightness)),
            UInt8(timerMin),
            UInt8(timerSec),
            UInt8(isTimerRunning ? 1 : 0),
            UInt8(totalPeriods)
        ])
        
        let ratioLabel = "\(period)/\(totalPeriods)"
        let clockTimeStr = String(format: "%02d:%02d", timerMin, timerSec)
        // The panel fits ~13 characters on the bottom line: "Q2 07:45" (period initial + number + clock).
        let initial = panelSafe(periodLabelText).uppercased().first(where: { $0.isLetter }).map(String.init) ?? "P"
        let lowerClockBannerLabel = "\(initial)\(period) \(clockTimeStr)"
        
        let stringPayload = [homeName, awayName, ratioLabel, lowerClockBannerLabel].map(panelSafe).joined(separator: "|")
        if let textData = stringPayload.data(using: .utf8) { packet.append(textData) }
        
        peripheral.writeValue(packet, for: characteristic, type: .withResponse)
        syncWatchData()
    }
    
    // MARK: - Board rename (CONFIG characteristic)
    /// Stages the new name on the board; the board confirms by notification, then we send apply (board reboots).
    func renameDevice(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        let isPrintableASCII = trimmed.utf8.allSatisfy { $0 >= 0x20 && $0 <= 0x7E }
        guard let peripheral = connectedPeripheral, let config = configCharacteristic else {
            renameStatus = String(localized: "Board not ready for renaming (firmware update needed?)")
            return
        }
        guard !trimmed.isEmpty, trimmed.utf8.count <= Self.deviceNameMaxLength, isPrintableASCII else {
            renameStatus = String(localized: "Name must be 1-\(Self.deviceNameMaxLength) plain characters")
            return
        }
        renameStatus = String(localized: "Renaming...")
        peripheral.writeValue(Data([cmdSetName]) + Data(trimmed.utf8), for: config, type: .withResponse)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == charUUID, let data = characteristic.value, data.count >= 5 {
            // [min, sec, running, period, battery%] (+ [flags, protocolVersion] from protocol v2)
            let battery = Int(data[4]), version = data.count >= 7 ? Int(data[6]) : 1
            DispatchQueue.main.async {
                self.batteryPercent = min(battery, 100)
                self.boardProtocolVersion = version
                self.telemetryReceived = true
            }
            return
        }
        guard characteristic.uuid == configUUID, let data = characteristic.value, data.count >= 2 else { return }
        let cmd = data[0], status = data[1]
        DispatchQueue.main.async {
            switch (cmd, status) {
            case (self.cmdSetName, 0):
                if let config = self.configCharacteristic {
                    peripheral.writeValue(Data([self.cmdApply]), for: config, type: .withResponse)
                }
            case (self.cmdApply, 0):
                self.renameStatus = String(localized: "Renamed. The board is restarting...")
            default:
                self.renameStatus = String(localized: "Board rejected the rename (code \(Int(status)))")
            }
        }
    }
    
    // MARK: - Safe Interruption & Auto Reconnect Logic
    func connect(to peripheral: CBPeripheral) {
        wasIntentionalDisconnect = false // Clear tracking flag
        centralManager.stopScan()
        connectedPeripheral = peripheral
        connectedPeripheral?.delegate = self
        centralManager.connect(peripheral, options: nil)
    }
    
    func disconnect() {
        wasIntentionalDisconnect = true // Lock tracking flag
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) { if central.state == .poweredOn { startScanning() } }
    func startScanning() { discoveredDevices.removeAll(); if centralManager.state == .poweredOn { centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil) } }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) { discoveredDevices.append(peripheral) }
        
        // FIXED: Auto-reconnect handshake recovery sequence
        if let deadPeripheral = connectedPeripheral, peripheral.identifier == deadPeripheral.identifier && !wasIntentionalDisconnect {
            print("Accidental dropout link spotted! Re-coupling with scoreboard panel automatically...")
            connect(to: peripheral)
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) { isConnected = true; peripheral.discoverServices([serviceUUID]) }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) { guard let services = peripheral.services else { return }; for service in services { peripheral.discoverCharacteristics([charUUID, configUUID], for: service) } }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == configUUID {
            configCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
            DispatchQueue.main.async { self.renameStatus = "" }
        }
        for characteristic in characteristics where characteristic.uuid == charUUID {
            targetCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
            syncDataToDisplay()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        targetCharacteristic = nil
        configCharacteristic = nil
        batteryPercent = nil
        boardProtocolVersion = nil
        telemetryReceived = false
        
        if wasIntentionalDisconnect {
            connectedPeripheral = nil
            startScanning()
        } else {
            // FIXED: Accidental signal dropout drop occurred - Keep clock ticking on iOS and scan to re-couple
            print("Scoreboard disconnected accidentally! Maintaining active session timers on screen...")
            if centralManager.state == .poweredOn {
                centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
            }
        }
    }
    
    // MARK: - Visual & Haptic Alerts System
    enum MatchEventType { case startEvent, periodAdvance, matchComplete }
    
    private func triggerHapticAlert(type: MatchEventType) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = Locale.current
        let ordinalString = formatter.string(from: NSNumber(value: period)) ?? "\(period)"
        
        // Configure Custom Display Text Labels
        switch type {
        case .startEvent:
            alertBannerTitle = String(localized: "▶️ Game Started!")
        case .periodAdvance:
            alertBannerTitle = String(localized: "⏰ \(ordinalString) \(periodLabelText) Starting!")
        case .matchComplete:
            alertBannerTitle = String(localized: "🏁 Full Match Complete!")
        }
        
        // Present the visual popup layout banner overlay
        withAnimation(.spring()) { showAlertBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation { self.showAlertBanner = false }
        }
        
        let style: UIImpactFeedbackGenerator.FeedbackStyle = (type == .startEvent) ? .medium : .heavy
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare(); generator.impactOccurred()
        if type == .matchComplete {
            for delay in [0.2, 0.4] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { generator.impactOccurred() } }
        }
        sendAlertPayloadToWatch(type: type, banner: alertBannerTitle)
    }
    
    private func sendAlertPayloadToWatch(type: MatchEventType, banner: String) {
        guard WCSession.default.activationState == .activated else { return }
        let alertID = type == .startEvent ? 1 : (type == .periodAdvance ? 2 : 3)
        WCSession.default.sendMessage(["triggerAlert": alertID, "alertText": banner], replyHandler: nil, errorHandler: nil)
    }
    
    func syncWatchData() {
        guard WCSession.default.activationState == .activated else { return }
        let info: [String: Any] = ["h": homeScore, "a": awayScore, "p": period, "r": isTimerRunning, "t": totalPeriods, "l": periodLabelText]
        WCSession.default.sendMessage(info, replyHandler: nil, errorHandler: nil)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            // Same limits as the iPhone UI, so the UInt8 conversions in syncDataToDisplay() can't trap.
            if let h = message["h"] as? Int { self.homeScore = min(max(h, 0), 99) }
            if let a = message["a"] as? Int { self.awayScore = min(max(a, 0), 99) }
            if let p = message["p"] as? Int { self.period = min(max(p, 1), self.totalPeriods) }
            if let r = message["r"] as? Bool { if r != self.isTimerRunning { self.toggleClock() } }
            self.syncDataToDisplay()
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    
    func sessionDidBecomeInactive(_ session: WCSession) {}
    
    func sessionDidDeactivate(_ session: WCSession) {}
}
