import SwiftUI
import CoreBluetooth
import WatchConnectivity
import Combine
import UserNotifications


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
    @Published var homeScore = 0 { didSet { if homeScore > oldValue { goalScored(byHome: true) } } }
    @Published var awayScore = 0 { didSet { if awayScore > oldValue { goalScored(byHome: false) } } }
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
    /// Firmware version reported by the board (nil on firmware that predates version numbers).
    @Published var boardFirmwareVersion: FirmwareVersion?
    /// Sends the bundled firmware to the board over Bluetooth.
    let firmwareUpdater = FirmwareUpdater()
    /// Names as boards advertise them: fresher than CBPeripheral.name, which iOS caches (it can show the old name after a rename).
    private var advertisedNames: [UUID: String] = [:]
    private var demoBoardName: String?
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
    /// True when the image inside the app has a newer version than the board reports. A board that reports no version is older.
    var firmwareUpdateAvailable: Bool {
        guard let bundled = firmwareUpdater.bundled, telemetryReceived else { return false }
        guard let boardVersion = boardFirmwareVersion else { return true }
        return boardVersion < bundled.version
    }
    
    /// The name of the board linked to the phone, so the screen can say whether it is showing real hardware.
    var connectedBoardName: String? {
        if let demo = demoBoardName { return demo }
        guard let peripheral = connectedPeripheral else { return nil }
        return advertisedNames[peripheral.identifier] ?? peripheral.name
    }
    
    /// Hiding elements needs protocol 4.
    var boardLacksIconSupport: Bool { telemetryReceived && (boardProtocolVersion ?? 1) < 6 }
    var boardLacksHideSupport: Bool { telemetryReceived && (boardProtocolVersion ?? 1) < 4 }
    var boardFirmwareOutdated: Bool { telemetryReceived && (boardProtocolVersion ?? 1) < Self.expectedProtocolVersion }
    
    // Visual Banner Alert State publishers
    @Published var alertBannerTitle = ""
    /// Goal animation: the text ("Goal by Whites"), which side scored, and whether it is showing.
    /// The emoji shown with goal alerts ("" = none). Saved on the phone; the board gets a 16 x 16 picture of it.
    @Published var goalIcon: String = UserDefaults.standard.object(forKey: GoalIcon.storeKey) as? String ?? "⚽" {
        didSet { UserDefaults.standard.set(goalIcon, forKey: GoalIcon.storeKey) }
    }
    @Published var goalText = ""
    @Published var goalByHome = true
    @Published var showGoal = false
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
    private let cmdAlertIcon: UInt8 = 0x06   // [0x06, first row] + 1-4 rows of 16 RGB565 pixels (big-endian); [0x06] alone removes the icon
    private var iconSentToBoard: String?     // the emoji the board currently holds, so it is sent once per connection
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
    
    /// The clock is based on the moment it will reach zero, so it stays right even if iOS suspends the app (screen locked, another app in front).
    private var clockEndDate: Date?
    
    func toggleClock() {
        isTimerRunning.toggle()
        if isTimerRunning {
            triggerHapticAlert(type: .startEvent)
            announceStartOnPanel()
            clockEndDate = Date().addingTimeInterval(Double(timerMin * 60 + timerSec))
            scheduleMatchEndNotification()
            nativeClockTimer?.invalidate()
            nativeClockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.handleClockTick()
            }
        } else {
            stopClock()
        }
        syncDataToDisplay()
    }
    
    private func stopClock() {
        nativeClockTimer?.invalidate()
        nativeClockTimer = nil
        clockEndDate = nil
        cancelMatchEndNotification()
    }
    
    /// Call when the app comes back to the foreground: catches the clock up with the time that passed.
    func refreshClockAfterBackground() {
        if isTimerRunning { handleClockTick() }
    }
    
    /// Half of the whole match is reached at the end of the middle period when the number of periods is even,
    /// and halfway through the middle period when it is odd.
    private var periodLengthSeconds: Int { (UserDefaults.standard.integer(forKey: "lastSavedMinutes") > 0 ? UserDefaults.standard.integer(forKey: "lastSavedMinutes") : 10) * 60 }
    private var halfTimeEndsPeriod: Bool { totalPeriods % 2 == 0 && period == totalPeriods / 2 }
    private var halfTimeInsidePeriod: Bool { totalPeriods % 2 == 1 && period == (totalPeriods + 1) / 2 }
    
    /// Seconds from now until half time, if it is still ahead in this period.
    private func secondsUntilHalfTime(remaining: Int) -> Int? {
        if halfTimeEndsPeriod { return remaining }
        if halfTimeInsidePeriod, remaining > periodLengthSeconds / 2 { return remaining - periodLengthSeconds / 2 }
        return nil
    }
    
    private func handleClockTick() {
        let previous = timerMin * 60 + timerSec
        let remaining = clockEndDate.map { Int(ceil($0.timeIntervalSinceNow)) } ?? (timerMin * 60 + timerSec - 1)
        if remaining > 0 {
            timerMin = remaining / 60
            timerSec = remaining % 60
            if halfTimeInsidePeriod, previous > periodLengthSeconds / 2, remaining <= periodLengthSeconds / 2 {
                triggerHapticAlert(type: .halfTime)
            }
        } else {
            let wasHalfTime = halfTimeEndsPeriod
            stopClock()
            isTimerRunning = false
            timerMin = 0
            timerSec = 0
            
            if period < totalPeriods {
                period += 1
                let savedMinutes = UserDefaults.standard.integer(forKey: "lastSavedMinutes")
                timerMin = savedMinutes > 0 ? savedMinutes : 10
                triggerHapticAlert(type: wasHalfTime ? .halfTime : .periodAdvance)
            } else {
                triggerHapticAlert(type: .matchComplete)
            }
        }
        syncDataToDisplay()
    }
    
    // MARK: - Match end notification (reaches the phone and the watch even when the app is not on screen)
    private let matchEndNotificationID = "matchEnd"
    private let halfTimeNotificationID = "halfTime"
    
    private func scheduleMatchEndNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        center.removePendingNotificationRequests(withIdentifiers: [matchEndNotificationID, halfTimeNotificationID])
        guard let end = clockEndDate else { return }
        let remaining = Int(end.timeIntervalSinceNow)
        func schedule(_ id: String, _ title: String, after seconds: Int) {
            guard seconds > 1 else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.sound = .default
            center.add(UNNotificationRequest(identifier: id, content: content,
                                             trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)))
        }
        if let untilHalf = secondsUntilHalfTime(remaining: remaining) { schedule(halfTimeNotificationID, String(localized: "⏸ Half Time!"), after: untilHalf) }
        if period >= totalPeriods { schedule(matchEndNotificationID, String(localized: "🏁 Full Match Complete!"), after: remaining) }   // only the last period ends the match
    }
    
    private func cancelMatchEndNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [matchEndNotificationID, halfTimeNotificationID])
    }
    
    /// Moves to another period. The clock stops and shows the full next period, ready to start.
    func setPeriod(_ newPeriod: Int) {
        let target = min(max(newPeriod, 1), totalPeriods)
        guard target != period else { return }
        period = target
        let savedMinutes = UserDefaults.standard.integer(forKey: "lastSavedMinutes")
        stopClock()
        isTimerRunning = false
        timerMin = savedMinutes > 0 ? savedMinutes : 10
        timerSec = 0
        syncDataToDisplay()
    }
    
    func changePeriod(by delta: Int) { setPeriod(period + delta) }
    
    func resetClockManual(minutes: Int) {
        stopClock()
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
        
        let names = boardSupportsNameIcons ? [panelText(homeName, firstSlot: 0), panelText(awayName, firstSlot: 2)] : [homeName, awayName].map(panelSafe)
        let stringPayload = (names + [ratioLabel, lowerClockBannerLabel].map(panelSafe)).joined(separator: "|")
        if boardSupportsNameIcons, let config = configCharacteristic { sendNameIcons(peripheral: peripheral, config: config) }
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
        case .halfTime: text = String(localized: "HALF TIME")
        case .goal(let label): text = label
        }
        return String(panelSafe(text).uppercased().split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ").prefix(16))
    }
    
    /// Tells the board to scroll the alert across the panel. Does nothing when no board is linked.
    func sendPanelAlert(_ kind: PanelAlertKind) {
        var element = PanelElement.alertGame
        if case .periodStart = kind { element = .alertPeriod }
        if case .halfTime = kind { element = .alertPeriod }
        guard panelVisibility[element] ?? true else { return }   // this alert is switched off
        var playback = AlertPlayback(text: panelAlertText(kind), color: panelColors[element] ?? element.defaultColor, start: Date())
        var isGoal = false
        if case .goal = kind { isGoal = true; playback.icon = GoalIcon.bitmap(for: goalIcon); playback.nameIcons = nameIconBitmaps }
        panelAlertPlayback = playback
        guard let peripheral = connectedPeripheral, let config = configCharacteristic else { return }
        var type: UInt8 = 1
        if case .periodStart = kind { type = 2 }
        if case .halfTime = kind { type = 2 }
        if isGoal, !boardLacksIconSupport, boardProtocolVersion != nil {
            sendGoalIconIfNeeded(peripheral: peripheral, config: config)
            type = 3
        }
        peripheral.writeValue(Data([cmdAlert, type]) + Data(panelAlertText(kind).utf8), for: config, type: .withResponse)
    }
    
    /// Sends the chosen emoji to the board as a 16 x 16 picture, four rows per write, once per connection and choice.
    private func sendGoalIconIfNeeded(peripheral: CBPeripheral, config: CBCharacteristic) {
        guard iconSentToBoard != goalIcon else { return }
        iconSentToBoard = goalIcon
        guard let pixels = GoalIcon.bitmap(for: goalIcon) else {
            peripheral.writeValue(Data([cmdAlertIcon]), for: config, type: .withResponse)    // no icon: the goal alert is text only
            return
        }
        for firstRow in stride(from: 0, to: GoalIcon.size, by: 4) {
            var data = Data([cmdAlertIcon, UInt8(firstRow)])
            for pixel in pixels[(firstRow * GoalIcon.size)..<((firstRow + 4) * GoalIcon.size)] {
                data.append(UInt8(pixel >> 8)); data.append(UInt8(pixel & 0xFF))
            }
            peripheral.writeValue(data, for: config, type: .withResponse)
        }
    }
    
    /// A game or period starts when the clock starts from the full period length; resuming after a pause does not alert.
    private func announceStartOnPanel() {
        let saved = UserDefaults.standard.integer(forKey: "lastSavedMinutes")
        guard timerMin == (saved > 0 ? saved : 10), timerSec == 0 else { return }
        sendPanelAlert(period == 1 ? .gameStart : .periodStart(period))
    }
    
    /// How the panel shows a name: ASCII capitals, up to 20 characters.
    /// Each emoji (up to two per team) becomes the byte of its picture slot (1-4); `firstSlot` is 0 for the home name and 2 for the away name.
    func panelText(_ text: String, firstSlot: Int = 0) -> String {
        var out = ""
        var used = 0
        for ch in text {
            if EmojiBitmap.isEmoji(ch) {
                if used < 2 { out.unicodeScalars.append(UnicodeScalar(UInt8(firstSlot + used + 1))); used += 1 }
            } else {
                out += panelSafe(String(ch))
            }
        }
        return String(out.uppercased().prefix(20))
    }
    
    // MARK: - Emoji in team names
    private let cmdNameIcon: UInt8 = 0x07    // [0x07, slot, first row] + rows of 10 RGB565 pixels (big-endian); [0x07, slot] clears the slot
    private var nameIconsSent = [String](repeating: "", count: 4)
    private var iconCache: [String: [UInt16]] = [:]
    
    var boardSupportsNameIcons: Bool { telemetryReceived && (boardProtocolVersion ?? 0) >= 7 }
    var boardLacksNameIconSupport: Bool { telemetryReceived && (boardProtocolVersion ?? 1) < 7 }
    
    /// The first two emoji of a name, one per picture slot.
    private func emojis(in name: String) -> [String] { Array(name.filter { EmojiBitmap.isEmoji($0) }.map(String.init).prefix(2)) }
    
    /// What each of the four slots (home 0-1, away 2-3) should show, "" for none.
    private func wantedNameEmojis() -> [String] {
        let home = emojis(in: homeName), away = emojis(in: awayName)
        return (0..<2).map { $0 < home.count ? home[$0] : "" } + (0..<2).map { $0 < away.count ? away[$0] : "" }
    }
    
    var hasEmojiInNames: Bool { wantedNameEmojis().contains { !$0.isEmpty } }
    
    private func nameBitmap(_ emoji: String) -> [UInt16] {
        if let cached = iconCache[emoji] { return cached }
        let bitmap = EmojiBitmap.make(emoji, size: EmojiBitmap.nameSize, fontSize: 8) ?? []
        iconCache[emoji] = bitmap
        return bitmap
    }
    
    /// The pictures behind the placeholders in the names, for the preview.
    var nameIconBitmaps: [[UInt16]] { wantedNameEmojis().map { $0.isEmpty ? [] : nameBitmap($0) } }
    
    /// Sends the pictures the board does not have yet: five rows per write, 100 bytes of pixels.
    private func sendNameIcons(peripheral: CBPeripheral, config: CBCharacteristic) {
        let wanted = wantedNameEmojis()
        for slot in 0..<4 where wanted[slot] != nameIconsSent[slot] {
            nameIconsSent[slot] = wanted[slot]
            let pixels = wanted[slot].isEmpty ? [] : nameBitmap(wanted[slot])
            guard pixels.count == EmojiBitmap.nameSize * EmojiBitmap.nameSize else {
                peripheral.writeValue(Data([cmdNameIcon, UInt8(slot)]), for: config, type: .withResponse)
                continue
            }
            for firstRow in [0, 5] {
                var data = Data([cmdNameIcon, UInt8(slot), UInt8(firstRow)])
                for pixel in pixels[(firstRow * EmojiBitmap.nameSize)..<((firstRow + 5) * EmojiBitmap.nameSize)] {
                    data.append(UInt8(pixel >> 8)); data.append(UInt8(pixel & 0xFF))
                }
                peripheral.writeValue(data, for: config, type: .withResponse)
            }
        }
    }
    
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
            // [min, sec, running, period, battery%] (+ [flags, protocolVersion] from protocol v2, + [major, minor, patch] firmware version from protocol v5)
            let battery = Int(data[4]), version = data.count >= 7 ? Int(data[6]) : 1
            let firmwareVersion: FirmwareVersion? = data.count >= 10 ? FirmwareVersion(Int(data[7]), Int(data[8]), Int(data[9])) : nil
            let clock = BoardClock(minutes: Int(data[0]), seconds: Int(data[1]), running: data[2] == 1, period: Int(data[3]), receivedAt: Date())
            DispatchQueue.main.async {
                self.boardClock = clock
                self.batteryPercent = min(battery, 100)
                self.boardProtocolVersion = version
                self.boardFirmwareVersion = firmwareVersion
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
            case (self.cmdColors, _), (self.cmdAlert, _), (self.cmdVisibility, _), (self.cmdAlertIcon, _), (self.cmdNameIcon, _):
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
        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String { advertisedNames[peripheral.identifier] = name }
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
        iconSentToBoard = nil
        nameIconsSent = ["", "", "", ""]
        batteryPercent = nil
        boardFirmwareVersion = nil
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
    
    // MARK: - Goal animation
    private var goalHideWork: DispatchWorkItem?
    
    /// Called whenever a score goes up, from the phone or the watch. Says "Goal by <team>" in the phone's language
    /// on the phone, on the panel (up to 16 characters) and on the watch.
    /// "Goal by <team>" for the phone (with the team's emoji as typed) and for the panel (each emoji replaced by its picture slot,
    /// or dropped when the board is too old to draw pictures).
    private func goalLabels(byHome: Bool) -> (phone: String, panel: String) {
        let rawName = (byHome ? homeName : awayName).trimmingCharacters(in: .whitespaces)
        let name = rawName.isEmpty ? (byHome ? String(localized: "HOME") : String(localized: "AWAY")) : rawName
        let panelName = (!isConnected || boardSupportsNameIcons) ? panelText(name, firstSlot: byHome ? 0 : 2) : name
        return (String(localized: "Goal by \(name)"), String(localized: "Goal by \(panelName)"))
    }
    
    /// Plays a goal alert for the home team on the panel and the preview without changing the score.
    func testGoalAlert() { sendPanelAlert(.goal(goalLabels(byHome: true).panel)) }
    
    private func goalScored(byHome: Bool) {
        guard !isDemo else { return }
        let labels = goalLabels(byHome: byHome)
        goalText = labels.phone
        goalByHome = byHome
        withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { showGoal = true }
        goalHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in withAnimation(.easeIn(duration: 0.3)) { self?.showGoal = false } }
        goalHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare(); generator.notificationOccurred(.success)
        sendPanelAlert(.goal(labels.panel))
        if WCSession.default.activationState == .activated {
            WCSession.default.sendMessage(["triggerAlert": 5, "alertText": (goalIcon.isEmpty ? "" : goalIcon + " ") + labels.phone], replyHandler: nil, errorHandler: nil)
        }
    }
    
    // MARK: - Visual & Haptic Alerts System
    enum MatchEventType { case startEvent, periodAdvance, matchComplete, halfTime }
    
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
        case .halfTime:
            alertBannerTitle = String(localized: "⏸ Half Time!")
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
        if type == .halfTime { sendPanelAlert(.halfTime) }
        sendAlertPayloadToWatch(type: type, banner: alertBannerTitle)
    }
    
    private func sendAlertPayloadToWatch(type: MatchEventType, banner: String) {
        guard WCSession.default.activationState == .activated else { return }
        let alertID: Int
        switch type { case .startEvent: alertID = 1; case .periodAdvance: alertID = 2; case .matchComplete: alertID = 3; case .halfTime: alertID = 4 }
        WCSession.default.sendMessage(["triggerAlert": alertID, "alertText": banner], replyHandler: nil, errorHandler: nil)
    }
    
    private var lastWatchContext = Date.distantPast
    private var lastWatchSignature = ""
    
    /// Sends the match state to the watch. A live message goes out when the watch app is reachable; the same state is also
    /// stored as the application context, which the watch reads whenever it wakes, so a message missed with the screen off can't leave it stale.
    func syncWatchData() {
        guard WCSession.default.activationState == .activated else { return }
        let info: [String: Any] = ["h": homeScore, "a": awayScore, "p": period, "r": isTimerRunning, "t": totalPeriods, "l": periodLabelText,
                                   "m": timerMin, "s": timerSec, "hn": homeName, "an": awayName, "ts": Date().timeIntervalSince1970]
        if WCSession.default.isReachable { WCSession.default.sendMessage(info, replyHandler: nil, errorHandler: nil) }
        let signature = "\(homeScore)|\(awayScore)|\(period)|\(isTimerRunning)|\(totalPeriods)|\(periodLabelText)|\(homeName)|\(awayName)" + (isTimerRunning ? "" : "|\(timerMin):\(timerSec)")
        if signature != lastWatchSignature || Date().timeIntervalSince(lastWatchContext) >= 5 {
            lastWatchSignature = signature; lastWatchContext = Date()
            try? WCSession.default.updateApplicationContext(info)
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            // Same limits as the iPhone UI, so the UInt8 conversions in syncDataToDisplay() can't trap.
            if let h = message["h"] as? Int { self.homeScore = min(max(h, 0), 99) }
            if let a = message["a"] as? Int { self.awayScore = min(max(a, 0), 99) }
            if let p = message["p"] as? Int { self.setPeriod(p) }   // changing period stops the clock and shows the full next period
            if message["rc"] as? Bool == true {
                let saved = UserDefaults.standard.integer(forKey: "lastSavedMinutes")
                self.resetClockManual(minutes: saved > 0 ? saved : 10)
            }
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
                case "available": boardProtocolVersion = 5; boardFirmwareVersion = FirmwareVersion(1, 0, 0); firmwareUpdater.demoSupported = true
                case "sending": boardFirmwareVersion = FirmwareVersion(1, 0, 0); firmwareUpdater.setDemo(.sending(0.42))
                case "done": firmwareUpdater.setDemo(.done)
                case "failed": firmwareUpdater.setDemo(.failed(String(localized: "The board is locked for 30 seconds after failed tries. Wait and try again.")))
                default: break
                }
            }
            demoBoardName = "Court 1"
        }
    }
    #endif
}

enum PanelAlertKind {
    case gameStart
    case periodStart(Int)
    case halfTime
    case goal(String)   // the full text, already translated
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
