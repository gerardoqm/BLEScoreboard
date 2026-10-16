import SwiftUI
import CoreBluetooth
import WatchConnectivity
import Combine

class AdvancedBLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate, WCSessionDelegate {
    
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectedPeripheral: CBPeripheral? = nil
    @Published var isConnected = false
    
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
    
    private var centralManager: CBCentralManager!
    private var targetCharacteristic: CBCharacteristic?
    private var nativeClockTimer: Timer? = nil
    
    let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789012")
    let charUUID    = CBUUID(string: "87654321-4321-4321-4321-210987654321")
    
    override init() {
        // Step 1: Call super.init FIRST to initialize the base NSObject and publishers
        super.init()
        
        // Step 2: Safe initialization of custom manager objects after super is ready
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
        // Step 3: Configure optional watch session attachments
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    // MARK: - Core Timer Loop
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
                // ==========================================
                // 🚨 TIME EXPIRED: AUTO ADVANCE MANAGEMENT
                // ==========================================
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
    
    // MARK: - BLE Transmission
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
    
    // Core Navigation Methods Configuration
    func startScanning() {
        discoveredDevices.removeAll()
        if centralManager.state == .poweredOn { centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil) }
    }
    
    func connect(to peripheral: CBPeripheral) {
        centralManager.stopScan(); connectedPeripheral = peripheral
        connectedPeripheral?.delegate = self; centralManager.connect(peripheral, options: nil)
    }
    
    func disconnect() { if let peripheral = connectedPeripheral { centralManager.cancelPeripheralConnection(peripheral) } }
    func centralManagerDidUpdateState(_ central: CBCentralManager) { if central.state == .poweredOn { startScanning() } }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) { discoveredDevices.append(peripheral) }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) { isConnected = true; peripheral.discoverServices([serviceUUID]) }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) { isConnected = false; connectedPeripheral = nil; targetCharacteristic = nil; startScanning() }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) { guard let services = peripheral.services else { return }; for service in services { peripheral.discoverCharacteristics([charUUID], for: service) } }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == charUUID { targetCharacteristic = characteristic; syncDataToDisplay() }
    }
    
    enum MatchEventType { case startEvent, periodAdvance, matchComplete }
    
    private func triggerHapticAlert(type: MatchEventType) {
        let style: UIImpactFeedbackGenerator.FeedbackStyle = (type == .startEvent) ? .medium : .heavy
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare(); generator.impactOccurred()
        if type == .matchComplete {
            for delay in [0.2, 0.4] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { generator.impactOccurred() } }
        }
        sendAlertPayloadToWatch(type: type)
    }
    
    private func sendAlertPayloadToWatch(type: MatchEventType) {
        guard WCSession.default.activationState == .activated else { return }
        let alertID = type == .startEvent ? 1 : (type == .periodAdvance ? 2 : 3)
        WCSession.default.sendMessage(["triggerAlert": alertID], replyHandler: nil, errorHandler: nil)
    }
    
    func syncWatchData() {
        guard WCSession.default.activationState == .activated else { return }
        let info: [String: Any] = ["h": homeScore, "a": awayScore, "p": period, "r": isTimerRunning, "t": totalPeriods, "l": periodLabelText]
        WCSession.default.sendMessage(info, replyHandler: nil, errorHandler: nil)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async {
            if let h = message["h"] as? Int { self.homeScore = h }
            if let a = message["a"] as? Int { self.awayScore = a }
            if let p = message["p"] as? Int { self.period = p }
            if let r = message["r"] as? Bool { if r != self.isTimerRunning { self.toggleClock() } }
            self.syncDataToDisplay()
        }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {}
}
