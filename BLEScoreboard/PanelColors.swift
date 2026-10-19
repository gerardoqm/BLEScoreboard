import SwiftUI
import UIKit

/// An 8-bit RGB color, the form stored on the phone and sent to the board.
struct RGB: Codable, Equatable {
    var r: UInt8, g: UInt8, b: UInt8
    
    init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
    
    init(_ color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        self.init(byte(red), byte(green), byte(blue))
    }
    
    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
    
    /// 16-bit RGB565, the format the LED panel uses. The board receives it big-endian.
    var rgb565: UInt16 { (UInt16(r & 0xF8) << 8) | (UInt16(g & 0xFC) << 3) | UInt16(b >> 3) }
}

/// Every piece of text on the panel that has its own color. The order is the wire order of the
/// "set colors" command: keep it in sync with the color indexes in scoreboard_BT_ESP32S3.ino.
enum PanelElement: String, CaseIterable, Identifiable {
    case timerRunning, timerStopped, period, homeName, homeScore, awayName, awayScore, alertGame, alertPeriod
    
    var id: String { rawValue }
    
    var title: LocalizedStringKey {
        switch self {
        case .timerRunning: return "Timer (running)"
        case .timerStopped: return "Timer (stopped)"
        case .period: return "Period"
        case .homeName: return "Home name"
        case .homeScore: return "Home score"
        case .awayName: return "Away name"
        case .awayScore: return "Away score"
        case .alertGame: return "Game start alert"
        case .alertPeriod: return "Period start alert"
        }
    }
    
    /// The colors the panel used before colors were configurable.
    var defaultColor: RGB {
        switch self {
        case .timerRunning: return RGB(0, 255, 0)
        case .timerStopped: return RGB(255, 120, 0)
        case .period: return RGB(255, 255, 0)
        case .homeName, .homeScore: return RGB(0, 120, 255)
        case .awayName, .awayScore: return RGB(255, 40, 40)
        case .alertGame: return RGB(0, 255, 0)
        case .alertPeriod: return RGB(0, 220, 255)
        }
    }
}

/// Saves the chosen colors on the phone so they can be sent again on every connection.
enum PanelColorStore {
    private static let key = "panelColors"
    
    static var defaults: [PanelElement: RGB] {
        Dictionary(uniqueKeysWithValues: PanelElement.allCases.map { ($0, $0.defaultColor) })
    }
    
    static func load() -> [PanelElement: RGB] {
        var colors = defaults
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: RGB].self, from: data) {
            for element in PanelElement.allCases { if let c = saved[element.rawValue] { colors[element] = c } }
        }
        return colors
    }
    
    static func save(_ colors: [PanelElement: RGB]) {
        let raw = Dictionary(uniqueKeysWithValues: colors.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// The panel's 3x5 pixel font, the same shapes the firmware draws.
enum LEDFont {
    static let glyphs: [Character: [String]] = [
        "0": ["111","101","101","101","111"],
        "1": ["010","110","010","010","111"],
        "2": ["111","001","111","100","111"],
        "3": ["111","001","111","001","111"],
        "4": ["101","101","111","001","001"],
        "5": ["111","100","111","001","111"],
        "6": ["111","100","111","101","111"],
        "7": ["111","001","010","010","010"],
        "8": ["111","101","111","101","111"],
        "9": ["111","101","111","001","111"],
        "A": ["010","101","111","101","101"],
        "B": ["110","101","110","101","110"],
        "C": ["011","100","100","100","011"],
        "D": ["110","101","101","101","110"],
        "E": ["111","100","110","100","111"],
        "F": ["111","100","110","100","100"],
        "G": ["011","100","101","101","011"],
        "H": ["101","101","111","101","101"],
        "I": ["111","010","010","010","111"],
        "J": ["001","001","001","101","010"],
        "K": ["101","101","110","101","101"],
        "L": ["100","100","100","100","111"],
        "M": ["101","111","111","101","101"],
        "N": ["111","101","101","101","101"],
        "O": ["010","101","101","101","010"],
        "P": ["110","101","110","100","100"],
        "Q": ["010","101","101","110","011"],
        "R": ["110","101","110","101","101"],
        "S": ["011","100","010","001","110"],
        "T": ["111","010","010","010","010"],
        "U": ["101","101","101","101","111"],
        "V": ["101","101","101","101","010"],
        "W": ["101","101","111","111","101"],
        "X": ["101","101","010","101","101"],
        "Y": ["101","101","010","010","010"],
        "Z": ["111","001","010","100","111"],
        "/": ["001","001","010","100","100"],
        ":": ["0","1","0","1","0"],
        " ": ["00","00","00","00","00"],
        "-": ["000","000","111","000","000"]
    ]
    
    static func glyph(_ ch: Character) -> [String] { glyphs[Character(ch.uppercased())] ?? glyphs["-"]! }
    
    /// Width of a string in font pixels, with one pixel between letters.
    static func units(_ text: String) -> Int {
        text.isEmpty ? 0 : text.reduce(-1) { $0 + glyph($1)[0].count + 1 }
    }
}

/// An 80 x 40 pixel picture of the panel, drawn with the same layout as the firmware.
struct PanelFrame {
    static let width = 80, height = 40
    var pixels = [RGB?](repeating: nil, count: width * height)
    
    mutating func set(_ x: Int, _ y: Int, _ c: RGB, clipX: Range<Int>? = nil) {
        guard x >= 0, y >= 0, x < Self.width, y < Self.height else { return }
        if let clip = clipX, !clip.contains(x) { return }
        pixels[y * Self.width + x] = c
    }
    
    mutating func text(_ t: String, x: Int, y: Int, scale s: Int, color: RGB, clipX: Range<Int>? = nil) {
        var cx = x
        for ch in t {
            let g = LEDFont.glyph(ch)
            for (row, line) in g.enumerated() {
                for (col, bit) in line.enumerated() where bit == "1" {
                    for dx in 0..<s { for dy in 0..<s { set(cx + col * s + dx, y + row * s + dy, color, clipX: clipX) } }
                }
            }
            cx += (g[0].count + 1) * s
        }
    }
    
    /// The scoreboard with sample data: timer top left, period top right, scores in the middle, names at the bottom.
    static func sample(colors: [PanelElement: RGB], clockRunning: Bool) -> PanelFrame {
        func c(_ e: PanelElement) -> RGB { colors[e] ?? e.defaultColor }
        var f = PanelFrame()
        f.text("07:45", x: 2, y: 1, scale: 2, color: c(clockRunning ? .timerRunning : .timerStopped))
        let period = "2/4"
        f.text(period, x: 78 - LEDFont.units(period) * 2, y: 1, scale: 2, color: c(.period))
        for j in 0..<26 { f.set(40, 12 + j, RGB(40, 40, 40)) }
        for (text, center, element) in [("12", 20, PanelElement.homeScore), ("9", 60, .awayScore)] {
            f.text(text, x: center - LEDFont.units(text) * 3 / 2, y: 13, scale: 3, color: c(element))
        }
        for (text, slotX, element) in [("LION", 2, PanelElement.homeName), ("BEAR", 42, .awayName)] {
            f.text(text, x: slotX + (36 - LEDFont.units(text) * 2) / 2, y: 29, scale: 2, color: c(element), clipX: slotX..<(slotX + 36))
        }
        return f
    }
}

extension PanelFrame {
    /// Same timing as the firmware: text scrolls right to left at 3x (18 ms per pixel) while a 2 pixel border flashes at 2 Hz.
    static func alertDuration(text: String) -> Double { Double((width + LEDFont.units(text) * 3) * 18 + 400) / 1000 }
    
    /// One frame of a start-of-game / start-of-period alert, or nil once it has finished.
    static func alert(text: String, color: RGB, elapsed: Double) -> PanelFrame? {
        guard elapsed < alertDuration(text: text) else { return nil }
        var f = PanelFrame()
        if Int(elapsed * 1000 / 250) % 2 == 0 {
            for i in 0..<width { for k in 0..<2 { f.set(i, k, color); f.set(i, height - 1 - k, color) } }
            for j in 0..<height { for k in 0..<2 { f.set(k, j, color); f.set(width - 1 - k, j, color) } }
        }
        f.text(text, x: width - Int(elapsed * 1000 / 18), y: 12, scale: 3, color: color)
        return f
    }
}

/// An alert playing in the preview. `frozenAt` holds it at one moment (used for screenshots).
struct AlertPlayback {
    let text: String
    let color: RGB
    let start: Date
    var frozenAt: Double? = nil
}

struct LEDPanelPreview: View {
    let colors: [PanelElement: RGB]
    let clockRunning: Bool
    var alert: AlertPlayback? = nil
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: alert == nil)) { timeline in
        Canvas { context, size in
            let playing = alert.flatMap { a in
                PanelFrame.alert(text: a.text, color: a.color, elapsed: a.frozenAt ?? timeline.date.timeIntervalSince(a.start))
            }
            let frame = playing ?? PanelFrame.sample(colors: colors, clockRunning: clockRunning)
            let pitch = size.width / CGFloat(PanelFrame.width)
            let dot = pitch * 0.82
            for y in 0..<PanelFrame.height {
                for x in 0..<PanelFrame.width {
                    let rect = CGRect(x: CGFloat(x) * pitch + (pitch - dot) / 2, y: CGFloat(y) * pitch + (pitch - dot) / 2, width: dot, height: dot)
                    let lit = frame.pixels[y * PanelFrame.width + x]
                    context.fill(Path(ellipseIn: rect), with: .color(lit?.color ?? Color(white: 0.1)))
                }
            }
        }
        }
        .aspectRatio(2, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel(Text("Panel preview"))
    }
}

/// Page for choosing the color of each piece of text on the panel.
struct PanelColorsView: View {
    @ObservedObject var ble: AdvancedBLEManager
    @State private var previewRunning = true
    @State private var alert: AlertPlayback?
    
    private static let presets: [RGB] = [
        RGB(255, 40, 40), RGB(255, 120, 0), RGB(255, 255, 0), RGB(0, 255, 0),
        RGB(0, 220, 255), RGB(0, 120, 255), RGB(255, 0, 200), RGB(255, 255, 255)
    ]
    
    private func binding(for element: PanelElement) -> Binding<Color> {
        Binding(get: { (ble.panelColors[element] ?? element.defaultColor).color },
                set: { ble.setColor(RGB($0), for: element) })
    }
    
    /// Plays the alert in the preview and, when a board is linked, on the board too.
    private func play(_ kind: PanelAlertKind) {
        let element: PanelElement = { if case .gameStart = kind { return .alertGame } else { return .alertPeriod } }()
        alert = AlertPlayback(text: ble.panelAlertText(kind), color: ble.panelColors[element] ?? element.defaultColor, start: Date())
        ble.sendPanelAlert(kind)
    }
    
    private func row(_ element: PanelElement) -> some View {
        let current = ble.panelColors[element] ?? element.defaultColor
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(element.title).font(.subheadline).bold()
                Spacer()
                ColorPicker("", selection: binding(for: element), supportsOpacity: false).labelsHidden()
            }
            HStack(spacing: 10) {
                ForEach(Array(Self.presets.enumerated()), id: \.offset) { _, preset in
                    Button { ble.setColor(preset, for: element) } label: {
                        Circle().fill(preset.color).frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Color.primary.opacity(preset == current ? 0.9 : 0.15), lineWidth: preset == current ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 10)
    }
    
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 16) {
                LEDPanelPreview(colors: ble.panelColors, clockRunning: previewRunning, alert: alert)
                Toggle("Preview with the clock running", isOn: $previewRunning).font(.footnote)
                
                if ble.boardLacksColorSupport {
                    Label("Update the board firmware to change colors.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                VStack(spacing: 0) {
                    ForEach(Array(PanelElement.allCases.enumerated()), id: \.element.id) { index, element in
                        row(element)
                        if index < PanelElement.allCases.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Button { play(.gameStart) } label: { Label("Play game start alert", systemImage: "play.circle").frame(maxWidth: .infinity) }
                        Button { play(.periodStart(2)) } label: { Label("Play period start alert", systemImage: "play.circle").frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.bordered).font(.footnote)
                    Text("Alerts also play on the board when it is linked.").font(.caption).foregroundColor(.secondary)
                }
                
                Button("Reset colors") { ble.resetColors() }.buttonStyle(.bordered).id("resetColors")
                
                Text("Colors are saved on the board and sent again each time you connect.")
                    .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            .padding()
        }
        .onAppear {
            // screenshots: `-playAlert game|period` shows an alert, `-alertFreeze 1.0` holds it at that many seconds
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-playAlert"), i + 1 < args.count {
                let kind: PanelAlertKind = args[i + 1] == "period" ? .periodStart(2) : .gameStart
                let element: PanelElement = args[i + 1] == "period" ? .alertPeriod : .alertGame
                var playback = AlertPlayback(text: ble.panelAlertText(kind), color: ble.panelColors[element] ?? element.defaultColor, start: Date())
                if let f = args.firstIndex(of: "-alertFreeze"), f + 1 < args.count { playback.frozenAt = Double(args[f + 1]) }
                alert = playback
            }
        }
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-colorsBottom") { proxy.scrollTo("resetColors", anchor: .bottom) } }  // screenshots
        }
        .navigationTitle("Panel Colors")
        .navigationBarTitleDisplayMode(.inline)
    }
}
