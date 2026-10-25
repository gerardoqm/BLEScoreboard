import SwiftUI
import CoreBluetooth

/// Pulsing radar rings shown while the app scans for scoreboards.
/// The rings are drawn from the clock, not from a stored animation, so they always start centered and in step
/// (an implicit repeat-forever animation could get stuck half way after the screen was rebuilt, for example on a language change).
struct ScanningRadarView: View {
    /// `-staticRadar` freezes the rings in an evenly spaced pose, used for tutorial screenshots.
    private let frozen = ProcessInfo.processInfo.arguments.contains("-staticRadar")
    private let frozenPhase: [Double] = [0.2, 0.55, 0.9]
    private let period = 2.4          // seconds for one ring to grow and fade
    private let spacing = 0.8         // delay between rings
    
    private func phase(_ ring: Int, at date: Date) -> Double {
        if frozen { return frozenPhase[ring] }
        let t = date.timeIntervalSinceReferenceDate - Double(ring) * spacing
        return t.truncatingRemainder(dividingBy: period) / period
    }
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: frozen)) { timeline in
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    let p = phase(ring, at: timeline.date)
                    let eased = 1 - (1 - p) * (1 - p)          // ease out
                    Circle()
                        .stroke(Color.green.opacity(0.7), lineWidth: 3)
                        .frame(width: 140, height: 140)
                        .scaleEffect(0.3 + 1.3 * eased)
                        .opacity(0.9 * (1 - p))
                }
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.green)
            }
            .frame(width: 220, height: 220)
        }
        .frame(width: 220, height: 220)
        .clipped()
        .accessibilityHidden(true)
    }
}

struct ContentView: View {
    @StateObject var ble = AdvancedBLEManager()
    @AppStorage("lastSavedMinutes") private var lastSavedMinutes: Int = 10
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var newBoardName = ""
    @State private var showFirmware = ProcessInfo.processInfo.arguments.contains("-showFirmware")  // also used for screenshots
    @State private var showColors = ProcessInfo.processInfo.arguments.contains("-showColors")  // also used for screenshots
    @State private var showPanelType = ProcessInfo.processInfo.arguments.contains("-showPanelType")  // also used for screenshots
    @State private var showAlertSettings = ProcessInfo.processInfo.arguments.contains("-showAlerts")  // also used for screenshots
    @State private var showTutorial = ProcessInfo.processInfo.arguments.contains("-showTutorial")  // also used for screenshots
    
    private var hasBoards: Bool { !ble.discoveredDevices.isEmpty || !ble.demoBoardNames.isEmpty }
    
    private func boardRow(name: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(name).bold()
            Spacer()
            Button("Link Display", action: action).buttonStyle(.borderedProminent)
        }
    }
    
    /// The unit name in the plural: "quarter" -> "quarters", "half" -> "halves", "tiempo" -> "tiempos", "mitad" -> "mitades".
    private func plural(_ word: String) -> String {
        if AppLanguage.current.code == "es" {
            return word + ((word.last.map { "aeiouáéíóú".contains($0) } ?? true) ? "s" : "es")
        }
        if ["s", "x", "z", "ch", "sh"].contains(where: { word.hasSuffix($0) }) { return word + "es" }
        if word.hasSuffix("y"), let before = word.dropLast().last, !"aeiou".contains(before) { return word.dropLast() + "ies" }
        if word.hasSuffix("f") { return word.dropLast() + "ves" }
        return word + "s"
    }
    
    /// The match title: "Match: 3rd of 4 quarters", "Partido: 1er de 4 tiempos" (the unit name is plural unless there is a single period).
    func matchTitle(period: Int, total: Int) -> String {
        let unit = ble.periodLabelText.trimmingCharacters(in: .whitespaces).lowercased()
        let name = unit.isEmpty ? defaultPeriodUnit().lowercased() : unit
        return tr("Match: \(ordinal(period)) of \(total) \(total == 1 ? name : plural(name))")
    }
    
    var body: some View {
        ZStack { // Enclosed within ZStack to project overlays
            NavigationStack {
                if !(ble.isConnected || ble.isSimulating) {
                    VStack {
                        Text("Select Your Scoreboard").font(.title2).bold().padding(.top)
                        Text("Select your board to avoid interference.").font(.caption).foregroundColor(.secondary)
                        List {
                            ForEach(ble.discoveredDevices, id: \.identifier) { device in
                                boardRow(name: device.name ?? tr("Unnamed Scoreboard")) { ble.connect(to: device) }
                            }
                            ForEach(ble.demoBoardNames, id: \.self) { name in
                                boardRow(name: name) { }
                            }
                        }
                        .refreshable { ble.startScanning() }
                        .overlay {
                            if !hasBoards {
                                ScrollView {
                                    VStack(spacing: 12) {
                                        if ble.isBluetoothOn {
                                            ScanningRadarView()
                                            Text("Searching for scoreboards...").font(.headline)
                                            Text("Make sure your scoreboard is powered on and nearby.")
                                                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                                            LinkHelpCard { showTutorial = true }.padding(.top, 8)
                                        } else {
                                            Image(systemName: "bolt.horizontal.circle").font(.system(size: 44)).foregroundColor(.orange)
                                            Text("Bluetooth is off. Turn it on to find scoreboards.")
                                                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                                        }
                                    }.padding(.horizontal, 20).padding(.bottom, 20)
                                }
                                .background(Color(.systemGroupedBackground))
                            }
                        }
                        Button { ble.startSimulation() } label: { Label("Try the simulated board", systemImage: "display") }
                            .buttonStyle(.bordered).padding(.top, 8)
                        Text("BLEScoreboard \(AppInfo.summary)").font(.caption2).foregroundColor(.secondary).padding(.bottom, 8)
                        if ble.isScanning && hasBoards {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Looking for more scoreboards...").font(.caption).foregroundColor(.secondary)
                            }.padding(.vertical, 10)
                        }
                    }
                    .navigationTitle("Find Scoreboards")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { LanguageMenu(ble: ble) }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showTutorial = true } label: { Image(systemName: "questionmark.circle") }
                                .accessibilityLabel(Text("Tutorial"))
                        }
                    }
                } else if verticalSizeClass == .compact && !showColors && !showFirmware && !showAlertSettings {
                    LandscapeScoreboardView(ble: ble)       // phone turned sideways: the whole screen is the scoreboard
                } else {
                    ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 20) {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Match Configuration").font(.caption).bold().foregroundColor(.secondary)
                                    Spacer()
                                    Text(LocalizedStringKey(ble.isSimulating ? "Simulator" : "Linked")).foregroundColor(ble.isSimulating ? .purple : .green).font(.caption2).bold()
                                    LanguageMenu(ble: ble)
                                    Button { showTutorial = true } label: { Image(systemName: "questionmark.circle") }
                                        .accessibilityLabel(Text("Tutorial"))
                                    Button(LocalizedStringKey(ble.isSimulating ? "Exit simulator" : "Disconnect")) { ble.disconnect() }.font(.caption2).bold().foregroundColor(.red).buttonStyle(.bordered).controlSize(.mini).tint(.red)
                                }
                                if ble.boardFirmwareOutdated {
                                    Label("Board firmware is outdated. Update it to use all features.", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption2).foregroundColor(.orange)
                                }
                                HStack {
                                    Image(systemName: "clock.badge.checkmark").foregroundColor(.purple)
                                    Text("Unit Name:").font(.subheadline).bold()
                                    TextField("e.g. Period, Cuarto, Tiempo", text: $ble.periodLabelText).textFieldStyle(.roundedBorder).font(.subheadline)
                                    if let battery = ble.batteryPercent {
                                        let tint: Color = battery < 15 ? .red : (battery < 50 ? .orange : .green)
                                        HStack(spacing: 3) {
                                            Image(systemName: battery < 15 ? "battery.0percent" : (battery < 50 ? "battery.50percent" : "battery.100percent"))
                                            Text("\(battery)%").font(.caption).bold().monospacedDigit()
                                        }
                                        .foregroundColor(tint)
                                        .fixedSize()
                                        .accessibilityElement(children: .ignore)
                                        .accessibilityLabel(Text("Battery \(battery)%"))
                                    }
                                }
                                if !ble.isSimulating {
                                HStack {
                                    Image(systemName: "pencil.circle").foregroundColor(.orange)
                                    Text("Board Name:").font(.subheadline).bold()
                                    TextField(ble.connectedBoardName ?? "Scoreboard", text: $newBoardName)
                                        .textFieldStyle(.roundedBorder).font(.subheadline)
                                        .onChange(of: newBoardName) { ble.renameStatus = "" }
                                    Button("Rename") { ble.renameDevice(to: newBoardName) }
                                        .buttonStyle(.bordered)
                                        .disabled(newBoardName.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                                if !ble.renameStatus.isEmpty {
                                    Text(ble.renameStatus).font(.caption2).foregroundColor(.secondary)
                                }
                                }
                                if ble.isConnected {
                                    Button { showFirmware = true } label: {
                                        HStack {
                                            Image(systemName: "arrow.down.circle").foregroundColor(.blue)
                                            Text("Board Firmware").font(.subheadline).bold()
                                            Spacer()
                                            if ble.firmwareUpdateAvailable { Text("Update available").font(.caption2).bold().foregroundColor(.blue) }
                                            Image(systemName: "chevron.right").font(.footnote).foregroundColor(.secondary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    if ble.boardSupportsMirror { MirrorBoardRow(ble: ble) }
                                    if ble.boardSupportsPanelType {
                                        Button { showPanelType = true } label: {
                                            HStack {
                                                Image(systemName: "square.grid.3x3").foregroundColor(.indigo)
                                                Text("Panel type").font(.subheadline).bold()
                                                Spacer()
                                                if let preset = ble.boardPanelPreset { Text(AdvancedBLEManager.panelPresetNames[preset]).font(.caption2).foregroundColor(.secondary) }
                                                Image(systemName: "chevron.right").font(.footnote).foregroundColor(.secondary)
                                            }
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                HStack(spacing: 10) {
                                    Button { showColors = true } label: {
                                        HStack {
                                            Image(systemName: "paintpalette").foregroundColor(.pink)
                                            Text("Panel Colors").font(.subheadline).bold()
                                            Image(systemName: "chevron.right").font(.footnote).foregroundColor(.secondary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    Spacer(minLength: 4)
                                    Image(systemName: "sun.max").foregroundColor(.yellow).accessibilityHidden(true)
                                    // 10...120 is the range the firmware accepts; show it as a percentage of the maximum
                                    Text("\(Int((ble.brightness / 120 * 100).rounded()))%")
                                        .font(.subheadline).bold().monospacedDigit()
                                    Stepper("LED Panel Brightness", value: $ble.brightness, in: 10...120, step: 5).labelsHidden()
                                }
                                .onChange(of: ble.brightness) { ble.syncDataToDisplay() }
                                Button { showAlertSettings = true } label: {
                                    HStack {
                                        Image(systemName: "speaker.wave.2").foregroundColor(.teal)
                                        Text("Alerts and Sound").font(.subheadline).bold()
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.footnote).foregroundColor(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider()
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Home Team").font(.caption2).bold().foregroundColor(.blue)
                                        TextField("REDS", text: $ble.homeName).textFieldStyle(.roundedBorder).multilineTextAlignment(.center)
                                    }
                                    Text("VS").font(.caption).bold().padding(.top, 15)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Away Team").font(.caption2).bold().foregroundColor(.red)
                                        TextField("BLUES", text: $ble.awayName).textFieldStyle(.roundedBorder).multilineTextAlignment(.center)
                                    }
                                }
                                if ble.isConnected && ble.boardLacksNameIconSupport && ble.hasEmojiInNames {
                                    Label("Update the board firmware to show emoji in team names on the board.", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption2).foregroundColor(.orange)
                                }
                            }
                            .padding().background(Color(.secondarySystemBackground)).cornerRadius(14).padding(.horizontal)
                            .onChange(of: ble.homeName) { ble.syncDataToDisplay() }
                            .onChange(of: ble.awayName) { ble.syncDataToDisplay() }
                            .onChange(of: ble.periodLabelText) { ble.syncDataToDisplay() }
                            
                                            // One box: period title, both scores and the countdown, to save screen space.
                            VStack(spacing: 10) {
                                Text(verbatim: matchTitle(period: ble.period, total: ble.totalPeriods))
                                    .font(.subheadline).bold().foregroundColor(.purple)
                                HStack(spacing: 12) {
                                    VStack(spacing: 2) {
                                        Text(ble.homeName.isEmpty ? tr("HOME") : ble.homeName.uppercased()).font(.subheadline).bold().foregroundColor(.blue).lineLimit(1)
                                        Text("\(ble.homeScore)").font(.system(size: 48, weight: .black, design: .monospaced))
                                        Stepper("", value: $ble.homeScore, in: 0...99, onEditingChanged: { _ in ble.syncDataToDisplay() }).labelsHidden()
                                    }.frame(maxWidth: .infinity)
                                    VStack(spacing: 2) {
                                        Text(ble.awayName.isEmpty ? tr("AWAY") : ble.awayName.uppercased()).font(.subheadline).bold().foregroundColor(.red).lineLimit(1)
                                        Text("\(ble.awayScore)").font(.system(size: 48, weight: .black, design: .monospaced))
                                        Stepper("", value: $ble.awayScore, in: 0...99, onEditingChanged: { _ in ble.syncDataToDisplay() }).labelsHidden()
                                    }.frame(maxWidth: .infinity)
                                }
                                Divider()
                                HStack(spacing: 10) {
                                    Text(String(format: "%02d:%02d", ble.timerMin, ble.timerSec)).font(.system(size: 34, weight: .bold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6).layoutPriority(1)
                                    Spacer(minLength: 4)
                                    Button(LocalizedStringKey(ble.isTimerRunning ? "Pause" : "Start")) { ble.toggleClock() }.buttonStyle(.borderedProminent).tint(ble.isTimerRunning ? .orange : .green).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                    Button { ble.resetClockManual(minutes: lastSavedMinutes) } label: { Image(systemName: "arrow.counterclockwise") }
                                        .accessibilityLabel(Text("Reset Clock")).buttonStyle(.bordered)
                                    Stepper("Min", value: Binding(get: { ble.timerMin }, set: { newValue in ble.timerMin = newValue; lastSavedMinutes = newValue; ble.syncDataToDisplay() }), in: 1...90).labelsHidden()
                                }
                                Divider()
                                HStack(spacing: 8) {
                                    Text("\(ble.periodLabelText): \(ble.period)").font(.subheadline).bold().lineLimit(1)
                                    Button { ble.changePeriod(by: -1) } label: { Image(systemName: "chevron.left") }
                                        .accessibilityLabel(Text("Previous period"))
                                        .disabled(ble.period <= 1)
                                        .buttonStyle(.bordered).controlSize(.small)
                                    Button { ble.changePeriod(by: 1) } label: { Image(systemName: "chevron.right") }
                                        .accessibilityLabel(Text("Next period"))
                                        .disabled(ble.period >= ble.totalPeriods)
                                        .buttonStyle(.bordered).controlSize(.small)
                                    Spacer()
                                    Text("Total:").font(.subheadline).bold()
                                    Picker("", selection: $ble.totalPeriods) {
                                        ForEach(1...9, id: \.self) { Text("\($0)").tag($0) }
                                    }.pickerStyle(.menu).onChange(of: ble.totalPeriods) {
                                        if ble.period > ble.totalPeriods { ble.setPeriod(ble.totalPeriods) }
                                        ble.syncDataToDisplay()
                                    }
                                }
                            }.padding().background(Color(.secondarySystemBackground)).cornerRadius(12).padding(.horizontal)
                            .id("matchSettings")
                            
                            SimulatedBoardCard(ble: ble).padding(.horizontal).id("boardPreview")
                            
                        }.padding(.top)
                    }
                    .onAppear {
                        if ble.demoScrollToBottom { proxy.scrollTo("matchSettings", anchor: .bottom) }
                        if ProcessInfo.processInfo.arguments.contains("-scrollPreview") { proxy.scrollTo("boardPreview", anchor: .bottom) }  // screenshots
                    }
                    .onChange(of: ble.isConnected) { newBoardName = "" }
                    .navigationDestination(isPresented: $showColors) { PanelColorsView(ble: ble) }
                    .navigationDestination(isPresented: $showPanelType) { PanelTypeView(ble: ble) }
                    .navigationDestination(isPresented: $showAlertSettings) { AlertSettingsView(ble: ble, alerts: ble.alerts) }
                    .navigationDestination(isPresented: $showFirmware) { FirmwareUpdateView(ble: ble, updater: ble.firmwareUpdater) }
                    }
                }
            }
            
            // Tutorial sheet is attached below on the ZStack
            // FIXED: NATIVE IPHONE VISUAL ALERT OVERLAY HUD DISPLAY
            // Goal animation: big text that pops in over the score, tinted with the scoring team's color
            if ble.showGoal {
                VStack(spacing: 6) {
                    if !ble.goalIcon.isEmpty { Text(ble.goalIcon).font(.system(size: 54)) }
                    Text(ble.goalText.uppercased())
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5).lineLimit(2)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 28).padding(.vertical, 22)
                .background((ble.goalByHome ? Color.blue : Color.red).opacity(0.92), in: RoundedRectangle(cornerRadius: 24))
                .shadow(radius: 12)
                .padding(.horizontal, 24)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
            }
            
            if ble.showAlertBanner {
                VStack {
                    HStack {
                        Text(ble.alertBannerTitle)
                            .font(.headline).foregroundColor(.white)
                            .padding()
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color.purple.opacity(0.95))
                    .cornerRadius(12)
                    .shadow(radius: 6)
                    .padding()
                    Spacer()
                }
                .transition(.move(edge: .top))
                .animation(.easeInOut, value: ble.showAlertBanner)
            }
        }
        .sheet(isPresented: $showTutorial) { TutorialView() }
        .onAppear {
            #if DEBUG
            // screenshots: `-landscape` turns the app sideways in the simulator
            if ProcessInfo.processInfo.arguments.contains("-landscape"),
               let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { ble.refreshClockAfterBackground() } }
        .environment(\.locale, ble.language.locale)       // SwiftUI texts follow the language picked in the app
    }
}

/// Language switch: follow the phone, or force English or Spanish. The watch follows too.
struct LanguageMenu: View {
    @ObservedObject var ble: AdvancedBLEManager
    
    var body: some View {
        Menu {
            Picker("Language", selection: $ble.language) {
                Text("Automatic").tag(AppLanguage.system)
                Text(verbatim: "English").tag(AppLanguage.english)
                Text(verbatim: "Español").tag(AppLanguage.spanish)
            }
        } label: {
            Image(systemName: "globe")
        }
        .accessibilityLabel(Text("Language"))
    }
}
