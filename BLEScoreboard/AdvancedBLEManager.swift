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
    @Published var homeName = "HOME"
    @Published var awayName = "AWAY"
    @Published var periodLabelText = "Period"
    
    // Visual Banner Alert State publishers
    @Published var alertBannerTitle = ""
    @Published var showAlertBanner = false
    
    private var centralManager: CBCentralManager!
    private var targetCharacteristic: CBCharacteristic?
    private var nativeClockTimer: Timer? = nil
    private var wasIntentionalDisconnect = false
    
    let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789012")
    let charUUID    = CBUUID(string: "87654321-4321-4321-4321-210987654321")
    
    override init() {
        super.init()
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
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = Locale.current
        let ordinalString = formatter.string(from: NSNumber(value: period)) ?? "\(period)"
        
        let ratioLabel = "\(period)/\(totalPeriods)"
        let clockTimeStr = String(format: "%02d:%02d", timerMin, timerSec)
        let lowerClockBannerLabel = "\(ordinalString) \(periodLabelText) \(clockTimeStr)"
        
        let stringPayload = "\(homeName)|\(awayName)|\(ratioLabel)|\(lowerClockBannerLabel)"
        if let textData = stringPayload.data(using: .utf8) { packet.append(textData) }
        
        peripheral.writeValue(packet, for: characteristic, type: .withResponse)
        syncWatchData()
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
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) { guard let services = peripheral.services else { return }; for service in services { peripheral.discoverCharacteristics([charUUID], for: service) } }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == charUUID { targetCharacteristic = characteristic; syncDataToDisplay() }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        targetCharacteristic = nil
        
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
            alertBannerTitle = "▶️ Game Started!"
        case .periodAdvance:
            alertBannerTitle = "⏰ \(ordinalString) \(periodLabelText) Starting!"
        case .matchComplete:
            alertBannerTitle = "🏁 Full Match Complete!"
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
