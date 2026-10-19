import SwiftUI
import Combine
import CoreBluetooth
import CryptoKit

/// A semantic version, `major.minor.patch`: patch for fixes, minor for compatible features, major for breaking changes.
struct FirmwareVersion: Comparable, Equatable, CustomStringConvertible {
    let major: Int, minor: Int, patch: Int
    
    init(_ major: Int, _ minor: Int, _ patch: Int) { self.major = major; self.minor = minor; self.patch = patch }
    
    init?(_ text: String) {
        let parts = text.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(parts[0], parts[1], parts[2])
    }
    
    var description: String { "\(major).\(minor).\(patch)" }
    
    static func < (a: FirmwareVersion, b: FirmwareVersion) -> Bool { (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch) }
}

/// The version of this app, from the project's version and build numbers.
enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
    static var summary: String { "\(version) (\(build))" }
}

/// The firmware image that ships inside the app, with its version.
/// It is produced locally by tools/bundle-firmware.sh and is never committed: the image contains the Wi-Fi and update
/// passwords from secrets.h, and firmware.json carries the update secret so the app can prove itself to the board
/// without asking anyone for a password.
struct BundledFirmware {
    let version: FirmwareVersion
    let secret: String?
    let image: Data
    
    static func load() -> BundledFirmware? {
        guard let binURL = Bundle.main.url(forResource: "scoreboard", withExtension: "bin"),
              let jsonURL = Bundle.main.url(forResource: "firmware", withExtension: "json"),
              let image = try? Data(contentsOf: binURL),
              let jsonData = try? Data(contentsOf: jsonURL),
              let info = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any],
              let versionText = info["version"] as? String, let version = FirmwareVersion(versionText) else { return nil }
        return BundledFirmware(version: version, secret: info["secret"] as? String, image: image)
    }
}

/// Standard CRC-32 (the one zlib uses). The board computes the same value while it receives the image.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var c = UInt32(index)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }
    
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return ~crc
    }
}

/// Sends the bundled firmware image to the board over Bluetooth.
///
/// Protocol (the OTA characteristic; see the firmware README): BEGIN returns a random nonce, AUTH answers it with
/// HMAC-SHA256(update password, nonce), START announces the size and CRC-32, DATA chunks go out without response
/// and the board acknowledges progress every 4 KB (we never run more than `window` bytes ahead), END makes the board
/// verify the CRC, switch to the new image and reboot.
final class FirmwareUpdater: ObservableObject {
    enum State: Equatable {
        case idle, authenticating, preparing
        case sending(Double)
        case finishing, done
        case failed(String)
    }
    
    @Published private(set) var state: State = .idle
    let bundled = BundledFirmware.load()
    
    private(set) var peripheral: CBPeripheral?
    private(set) var characteristic: CBCharacteristic?
    /// Set only by the screenshot demo.
    var demoSupported = false
    
    private var secret = ""
    private var image = Data()
    private var offset = 0
    private var acked = 0
    private var endSent = false
    private var lastProgress = Date()
    private var watchdog: Timer?
    private let window = 8192
    
    private let opBegin: UInt8 = 0x01, opAuth: UInt8 = 0x02, opStart: UInt8 = 0x03, opData: UInt8 = 0x04
    private let opAck: UInt8 = 0x05, opEnd: UInt8 = 0x06, opAbort: UInt8 = 0x07
    
    var isSupportedByBoard: Bool { characteristic != nil || demoSupported }
    var isRunning: Bool {
        switch state {
        case .idle, .done, .failed: return false
        default: return true
        }
    }
    
    func configure(peripheral: CBPeripheral?, characteristic: CBCharacteristic?) {
        self.peripheral = peripheral
        self.characteristic = characteristic
        if peripheral == nil && isRunning && state != .finishing {
            fail(String(localized: "The Bluetooth connection was lost during the update."))
        }
    }
    
    /// Whether the bundled image can be sent: the app needs the image and the secret the board expects.
    var canUpdate: Bool { bundled?.secret?.isEmpty == false && peripheral != nil && characteristic != nil }
    
    func start() {
        guard !isRunning, let bundled, let secret = bundled.secret, !secret.isEmpty, peripheral != nil, characteristic != nil else { return }
        self.secret = secret
        image = bundled.image
        print("[fwupdate] start: image \(image.count) bytes, write size \(peripheral?.maximumWriteValueLength(for: .withoutResponse) ?? 0)")
        offset = 0; acked = 0; endSent = false
        state = .authenticating
        touch()
        startWatchdog()
        send(Data([opBegin]))
    }
    
    func cancel() {
        guard isRunning else { return }
        send(Data([opAbort]))
        fail(String(localized: "Update cancelled."), withDetail: false)
    }
    
    func resetMessage() { if case .failed = state { state = .idle } else if state == .done { state = .idle } }
    
    // MARK: - Messages from the board
    func handle(_ data: Data) {
        guard let op = data.first, isRunning else { return }
        touch()
        if op == opAck, data.count >= 5 {
            acked = Int(UInt32(data[1]) | UInt32(data[2]) << 8 | UInt32(data[3]) << 16 | UInt32(data[4]) << 24)
            if acked % 65536 < 2048 { print("[fwupdate] confirmed \(acked)/\(image.count)") }
            if case .sending = state { state = .sending(min(1, Double(acked) / Double(max(image.count, 1)))) }
            pump()
            return
        }
        guard data.count >= 2 else { return }
        let status = data[1]
        print("[fwupdate] board replied op \(op) status \(status)")
        switch op {
        case opBegin:
            guard status == 0, data.count >= 18 else { return fail(status: status) }
            let nonce = data.subdata(in: 2..<18)
            let mac = HMAC<SHA256>.authenticationCode(for: nonce, using: SymmetricKey(data: Data(secret.utf8)))
            send(Data([opAuth]) + Data(mac))
        case opAuth:
            guard status == 0 else { return fail(status: status) }
            state = .preparing
            var message = Data([opStart])
            message.append(le32(UInt32(image.count)))
            message.append(le32(CRC32.checksum(image)))
            send(message)
        case opStart:
            guard status == 0 else { return fail(status: status) }
            state = .sending(0)
            pump()
        case opEnd:
            if status == 0 { finish(.done) } else { fail(status: status) }
        default:
            break
        }
    }
    
    /// Sends as much of the image as the Bluetooth stack and the board's window allow.
    func pump() {
        guard case .sending = state, let peripheral, let characteristic else { return }
        let payload = min(peripheral.maximumWriteValueLength(for: .withoutResponse) - 1, 180)
        guard payload > 0 else { return }
        while offset < image.count, peripheral.canSendWriteWithoutResponse, offset - acked < window {
            let end = min(offset + payload, image.count)
            peripheral.writeValue(Data([opData]) + image.subdata(in: offset..<end), for: characteristic, type: .withoutResponse)
            offset = end
        }
        if offset >= image.count, acked >= image.count, !endSent {
            endSent = true
            state = .finishing
            send(Data([opEnd]))
        }
    }
    
    // MARK: - Helpers
    private func send(_ data: Data) {
        guard let peripheral, let characteristic else { return }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
    
    private func le32(_ value: UInt32) -> Data { Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)]) }
    
    private func touch() { lastProgress = Date() }
    
    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, self.isRunning, Date().timeIntervalSince(self.lastProgress) > 20 else { return }
            self.send(Data([self.opAbort]))
            self.fail(String(localized: "The update stalled. Move the phone closer to the board and try again."))
        }
    }
    
    private func finish(_ final: State) {
        watchdog?.invalidate(); watchdog = nil
        state = final
    }
    
    /// A failure message ends with where the transfer stopped, e.g. "[48000/1234000 sent, 45056 confirmed]", so a report says how far it got.
    private func fail(_ message: String, withDetail: Bool = true) {
        let detail = "[\(offset)/\(image.count) sent, \(acked) confirmed]"
        print("[fwupdate] failed: \(message) \(detail)")
        finish(.failed(withDetail ? "\(message) \(detail)" : message))
    }
    
    private func fail(status: UInt8) {
        let message: String
        switch status {
        case 3: message = String(localized: "The board did not accept this app's update key. Rebuild the app with tools/bundle-firmware.sh after flashing the board.")
        case 7: message = String(localized: "The board is locked for 30 seconds after failed tries. Wait and try again.")
        case 4: message = String(localized: "The firmware does not fit on the board.")
        case 5: message = String(localized: "The board could not write the firmware.")
        case 6: message = String(localized: "The firmware did not pass the board's check, so nothing was changed.")
        case 2: message = String(localized: "The board was busy. Try again.")
        default: message = String(localized: "Update failed (code \(Int(status))).")
        }
        fail(message)
    }
    
    #if DEBUG
    /// Screenshot support: shows a state without a board.
    func setDemo(_ newState: State) { demoSupported = true; state = newState }
    #endif
}

/// Page for updating the board's firmware over Bluetooth.
struct FirmwareUpdateView: View {
    @ObservedObject var ble: AdvancedBLEManager
    @ObservedObject var updater: FirmwareUpdater
    
    private var boardVersion: String {
        if let version = ble.boardFirmwareVersion { return version.description }
        return ble.telemetryReceived ? String(localized: "Older, no version number") : String(localized: "Unknown")
    }
    
    private var appFirmwareVersion: String {
        updater.bundled.map { $0.version.description } ?? String(localized: "No firmware in this app")
    }
    
    private func versionRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack { Text(title).font(.subheadline).bold(); Spacer(); Text(value).font(.subheadline).foregroundColor(.secondary) }
    }
    
    @ViewBuilder private var progress: some View {
        switch updater.state {
        case .idle:
            EmptyView()
        case .authenticating:
            Label("Connecting to the board...", systemImage: "key")
        case .preparing:
            Label("Preparing the board...", systemImage: "gearshape")
        case .sending(let fraction):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: fraction)
                Text("Sending firmware \(Int((fraction * 100).rounded()))%").font(.footnote).foregroundColor(.secondary)
            }
        case .finishing:
            Label("Checking and installing...", systemImage: "checkmark.shield")
        case .done:
            Label("Done. The board is restarting with the new firmware.", systemImage: "checkmark.circle.fill").foregroundColor(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    versionRow("Firmware on the board", boardVersion)
                    Divider()
                    versionRow("Firmware in this app", appFirmwareVersion)
                    Divider()
                    versionRow("App version", AppInfo.summary)
                    if ble.firmwareUpdateAvailable {
                        Label("A newer firmware is available for this board.", systemImage: "arrow.down.circle.fill")
                            .font(.footnote).foregroundColor(.blue).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding().background(Color(.secondarySystemBackground)).cornerRadius(12)
                
                if ble.telemetryReceived && !updater.isSupportedByBoard {
                    Label("This board needs a one-time USB update before it can update over Bluetooth.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundColor(.orange).frame(maxWidth: .infinity, alignment: .leading)
                }
                if updater.bundled == nil {
                    Label("This copy of the app does not include a firmware image. Build it with tools/bundle-firmware.sh.", systemImage: "info.circle")
                        .font(.footnote).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                } else if updater.bundled?.secret?.isEmpty != false {
                    Label("The firmware in this app has no update key. Rebuild it with tools/bundle-firmware.sh.", systemImage: "info.circle")
                        .font(.footnote).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                
                progress.frame(maxWidth: .infinity, alignment: .leading).font(.subheadline)
                
                if updater.isRunning {
                    Button("Cancel", role: .destructive) { updater.cancel() }.buttonStyle(.bordered)
                } else {
                    Button { updater.resetMessage(); updater.start() } label: {
                        Text(ble.firmwareUpdateAvailable ? "Update board firmware" : "Reinstall board firmware").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!ble.isConnected || !updater.isSupportedByBoard || !updater.canUpdate)
                }
                
                Text("Keep the phone next to the board and this screen open. It takes one to three minutes, the panel shows a progress bar, and the board restarts when it is done. If anything goes wrong the board keeps its current firmware.")
                    .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("Board Firmware")
        .navigationBarTitleDisplayMode(.inline)
    }
}
