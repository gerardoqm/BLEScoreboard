import SwiftUI
import CoreBluetooth
import WatchConnectivity
import Combine


class AdvancedBLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate, WCSessionDelegate {
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectedPeripheral: CBPeripheral? = nil
    @Published var isConnected = false
    @Published var isScanning = false
    /// Fake boards for screenshots (debug builds, `-demo list`). Always empty in release builds.
    @Published var demoBoardNames: [String] = []
    @Published var demoScrollToBottom = false
    private var isDemo = false
    @Published var isBluetoothOn = true
    
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
    @Published var panelColors: [PanelElement: RGB] = PanelColorStore.load()
    /// Match screen without a physical board: the simulated panel is the only display.
    @Published var isSimulating = false
    /// The alert currently playing on the simulated panel (the board plays the same one).
    @Published var panelAlertPlayback: AlertPlayback?
    /// The board's own clock, from its telemetry, used to show whether it is in sync with the app.
    @Published var boardClock: BoardClock?
    @Published var panelVisibility: [PanelElement: Bool] = PanelVisibilityStore.load()
    /// Firmware build number reported by the board (protocol 5 and later).
    @Published var boardFirmwareBuild: Int?
    /// Sends the bundled firmware to the board over Bluetooth.
    let firmwareUpdater = FirmwareUpdater()
    private var colorSendWork: DispatchWorkItem?
    private var visibilitySendWork: DispatchWorkItem?
    
    // Board telemetry (notification on the main characteristic)
    @Published var batteryPercent: Int? = nil
    @Published var boardProtocolVersion: Int? = nil
    @Published var telemetryReceived = false
    /// Telemetry layout version this app expects. Keep in sync with PROTOCOL_VERSION in scoreboard_BT_ESP32S3.ino.
    static let expectedProtocolVersion = 5
    /// Colors need protocol 3. Unknown until the board's first telemetry arrives, so never warn before that.
    var boardLacksColorSupport: Bool { telemetryReceived && (boardProtocolVersion ?? 1) < 3 }
    /// True when the image inside the app is newer than what the board reports.
    var firmwareUpdateAvailable: Bool {
        guard let bundled = firmwareUpdater.bundled, let boardProtocol = boardProtocolVersion else { return false }
        if boardProtocol != bundled.protocolVersion { return boardProtocol < bundled.protocolVersion }
        return (boardFirmwareBuild ?? 0) < bundled.build
    }
    
    /// Hiding elements needs protocol 4.
    var boardLacksHideSupport: Bool { telemetryReceived && (boardProtocolVersion ?? 1) < 4 }
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
    let otaUUID     = CBUUID(string: "87654321-4321-4321-4321-210987654323")
    // CONFIG characteristic: [cmd, args...] writes, [cmd, status] notifications (status 0 = OK).
    // Keep in sync with scoreboard_BT_ESP32S3.ino.
    let configUUID  = CBUUID(string: "87654321-4321-4321-4321-210987654322")
    private let cmdSetName: UInt8 = 0x01
    private let cmdApply: UInt8 = 0x02
    private let cmdColors: UInt8 = 0x03   // [0x03] + 9 x RGB565 big-endian, in PanelElement order
    private let cmdVisibility: UInt8 = 0x05  // [0x05, mask low byte, mask high byte]; bit i = PanelElement i is shown
    private let cmdAlert: UInt8 = 0x04    // [0x04, type (1 game start, 2 period start)] + 1-16 ASCII characters
    static let deviceNameMaxLength = 20
    
    override init() {
        super.init()
        let savedMinutes = UserDefaults.standard.integer(forKey: "lastSavedMinutes")
        if savedMinutes > 0 { timerMin = savedMinutes }
        #if DEBUG
        applyDemoModeIfRequested()
        #endif
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
            announceStartOnPanel()
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
        syncWatchData()  // the watch follows the phone even when no board is linked
        guard !firmwareUpdater.isRunning else { return }   // keep the link free for the firmware transfer
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
    }
    
    // MARK: - Panel colors (CONFIG characteristic)
    func setColor(_ rgb: RGB, for element: PanelElement) {
        panelColors[element] = rgb
        PanelColorStore.save(panelColors)
        scheduleColorSend()
    }
    
    func resetColors() {
        panelColors = PanelColorStore.defaults
        PanelColorStore.save(panelColors)
        sendColors()
    }
    
    func setVisible(_ visible: Bool, for element: PanelElement) {
        panelVisibility[element.visibilityKey] = visible
        PanelVisibilityStore.save(panelVisibility)
        visibilitySendWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sendVisibility() }
        visibilitySendWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
    
    func sendVisibility() {
        guard let peripheral = connectedPeripheral, let config = configCharacteristic else { return }
        let mask = PanelVisibilityStore.mask(panelVisibility)
        peripheral.writeValue(Data([cmdVisibility, UInt8(mask & 0xFF), UInt8(mask >> 8)]), for: config, type: .withResponse)
    }
    
    /// A color picker drag produces many changes; send once it settles.
    private func scheduleColorSend() {
        colorSendWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sendColors() }
        colorSendWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    
    // MARK: - Panel alerts
    /// Text for the panel's start alerts: ASCII only, capitals, at most 16 characters.
    func panelAlertText(_ kind: PanelAlertKind) -> String {
        let text: String
        switch kind {
        case .gameStart: text = String(localized: "GAME START")
        case .periodStart(let number): text = String(localized: "PERIOD \(number)")
        }
        return String(panelSafe(text).uppercased().prefix(16))
    }
    
    /// Tells the board to scroll the alert across the panel. Does nothing when no board is linked.
    func sendPanelAlert(_ kind: PanelAlertKind) {
        var element = PanelElement.alertGame
        if case .periodStart = kind { element = .alertPeriod }
        guard panelVisibility[element] ?? true else { return }   // this alert is switched off
        panelAlertPlayback = AlertPlayback(text: panelAlertText(kind), color: panelColors[element] ?? element.defaultColor, start: Date())
        guard let peripheral = connectedPeripheral, let config = configCharacteristic else { return }
        var type: UInt8 = 1
        if case .periodStart = kind { type = 2 }
        peripheral.writeValue(Data([cmdAlert, type]) + Data(panelAlertText(kind).utf8), for: config, type: .withResponse)
    }
    
    /// A game or period starts when the clock starts from the full period length; resuming after a pause does not alert.
    private func announceStartOnPanel() {
        let saved = UserDefaults.standard.integer(forKey: "lastSavedMinutes")
        guard timerMin == (saved > 0 ? saved : 10), timerSec == 0 else { return }
        sendPanelAlert(period == 1 ? .gameStart : .periodStart(period))
    }
    
    /// How the panel shows a name: ASCII capitals, up to 20 characters.
    func panelText(_ text: String) -> String { String(panelSafe(text).uppercased().prefix(20)) }
    
    func sendColors() {
        guard let peripheral = connectedPeripheral, let config = configCharacteristic else { return }
        var data = Data([cmdColors])
        for element in PanelElement.allCases {
            let value = (panelColors[element] ?? element.defaultColor).rgb565
            data.append(UInt8(value >> 8)); data.append(UInt8(value & 0xFF))
        }
        peripheral.writeValue(data, for: config, type: .withResponse)
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
        if characteristic.uuid == otaUUID, let data = characteristic.value {
            DispatchQueue.main.async { self.firmwareUpdater.handle(data) }
            return
        }
        if characteristic.uuid == charUUID, let data = characteristic.value, data.count >= 5 {
            // [min, sec, running, period, battery%] (+ [flags, protocolVersion] from protocol v2)
            let battery = Int(data[4]), version = data.count >= 7 ? Int(data[6]) : 1
            let build: Int? = data.count >= 8 ? Int(data[7]) : nil
            let clock = BoardClock(minutes: Int(data[0]), seconds: Int(data[1]), running: data[2] == 1, period: Int(data[3]), receivedAt: Date())
            DispatchQueue.main.async {
                self.boardClock = clock
                self.batteryPercent = min(battery, 100)
                self.boardProtocolVersion = version
                self.boardFirmwareBuild = build
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
            case (self.cmdColors, _), (self.cmdAlert, _), (self.cmdVisibility, _):
                break   // colors need no feedback; boards without protocol 3 are reported by the version check
            case (self.cmdApply, 0):
                self.renameStatus = String(localized: "Renamed. The board is restarting...")
            default:
                self.renameStatus = String(localized: "Board rejected the rename (code \(Int(status)))")
            }
        }
    }
    
    // MARK: - Safe Interruption & Auto Reconnect Logic
    func connect(to peripheral: CBPeripheral) {
        isSimulating = false
        wasIntentionalDisconnect = false // Clear tracking flag
        centralManager.stopScan()
        isScanning = false
        connectedPeripheral = peripheral
        connectedPeripheral?.delegate = self
        centralManager.connect(peripheral, options: nil)
    }
    
    func startSimulation() { isSimulating = true }
    
    func disconnect() {
        if isSimulating { isSimulating = false; return }   // leaving the simulated board
        wasIntentionalDisconnect = true // Lock tracking flag
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if isDemo { return }
        isBluetoothOn = central.state == .poweredOn
        if central.state == .poweredOn { startScanning() } else { isScanning = false }
    }
    func startScanning() {
        discoveredDevices.removeAll()
        if centralManager.state == .poweredOn {
            isScanning = true
            centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) { discoveredDevices.append(peripheral) }
        
        // FIXED: Auto-reconnect handshake recovery sequence
        if let deadPeripheral = connectedPeripheral, peripheral.identifier == deadPeripheral.identifier && !wasIntentionalDisconnect {
            print("Accidental dropout link spotted! Re-coupling with scoreboard panel automatically...")
            connect(to: peripheral)
        }
    }
    /// The Bluetooth stack can take more firmware chunks.
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) { firmwareUpdater.pump() }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) { isConnected = true; peripheral.discoverServices([serviceUUID]) }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) { guard let services = peripheral.services else { return }; for service in services { peripheral.discoverCharacteristics([charUUID, configUUID, otaUUID], for: service) } }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == otaUUID {
            peripheral.setNotifyValue(true, for: characteristic)
            firmwareUpdater.configure(peripheral: peripheral, characteristic: characteristic)
        }
        for characteristic in characteristics where characteristic.uuid == configUUID {
            configCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
            DispatchQueue.main.async { self.renameStatus = ""; self.sendColors(); self.sendVisibility() }
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
        boardFirmwareBuild = nil
        firmwareUpdater.configure(peripheral: nil, characteristic: nil)
        boardClock = nil
        boardProtocolVersion = nil
        telemetryReceived = false
        
        if wasIntentionalDisconnect {
            connectedPeripheral = nil
            startScanning()
        } else {
            // FIXED: Accidental signal dropout drop occurred - Keep clock ticking on iOS and scan to re-couple
            print("Scoreboard disconnected accidentally! Maintaining active session timers on screen...")
            if centralManager.state == .poweredOn {
                isScanning = true
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

    #if DEBUG
    /// Screenshot support for the simulator (it has no Bluetooth). Launch with `-demo scanning|list|connected|connected-bottom`.
    private func applyDemoModeIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demo"), i + 1 < args.count else { return }
        isDemo = true
        isBluetoothOn = true
        switch args[i + 1] {
        case "scanning":
            isScanning = true
        case "simulate", "simulate-alert":
            isSimulating = true
            if args[i + 1] == "simulate-alert" {
                panelAlertPlayback = AlertPlayback(text: panelAlertText(.gameStart), color: (panelColors[.alertGame] ?? PanelElement.alertGame.defaultColor), start: Date(), frozenAt: 1.1)
            }
            homeName = "LION"; awayName = "BEAR"
            homeScore = 12; awayScore = 9
            period = 2; totalPeriods = 4
            timerMin = 7; timerSec = 45
            periodLabelText = String(localized: "Period")
        case "list":
            isScanning = true
            demoBoardNames = ["Scoreboard_Beta", "Court 2"]
        default:
            isConnected = true
            homeName = "LION"; awayName = "BEAR"
            homeScore = 12; awayScore = 9
            period = 2; totalPeriods = 4
            timerMin = 7; timerSec = 45
            periodLabelText = String(localized: "Period")
            batteryPercent = 82; boardProtocolVersion = Self.expectedProtocolVersion; telemetryReceived = true
            demoScrollToBottom = args[i + 1] == "connected-bottom"
            if let f = args.firstIndex(of: "-fwDemo"), f + 1 < args.count {
                switch args[f + 1] {
                case "available": boardProtocolVersion = 4; boardFirmwareBuild = nil; firmwareUpdater.demoSupported = true
                case "sending": boardProtocolVersion = 4; firmwareUpdater.setDemo(.sending(0.42))
                case "done": firmwareUpdater.setDemo(.done)
                case "failed": firmwareUpdater.setDemo(.failed(String(localized: "Wrong update password.")))
                default: break
                }
            }
        }
    }
    #endif
}

enum PanelAlertKind {
    case gameStart
    case periodStart(Int)
}

/// The clock the board reports in its telemetry, with the time it was received.
struct BoardClock {
    let minutes: Int
    let seconds: Int
    let running: Bool
    let period: Int
    let receivedAt: Date
    
    /// What the board's clock reads now, assuming it kept counting since the report.
    func seconds(at now: Date) -> Int {
        let reported = minutes * 60 + seconds
        return running ? max(0, reported - Int(now.timeIntervalSince(receivedAt))) : reported
    }
}
