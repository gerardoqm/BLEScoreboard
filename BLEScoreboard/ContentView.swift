import SwiftUI
import CoreBluetooth

/// Pulsing radar rings shown while the app scans for scoreboards.
struct ScanningRadarView: View {
    @State private var pulse = false
    /// `-staticRadar` freezes the rings in an evenly spaced pose, used for tutorial screenshots.
    private let frozen = ProcessInfo.processInfo.arguments.contains("-staticRadar")
    private let frozenScale: [CGFloat] = [0.55, 0.95, 1.35]
    private let frozenOpacity: [Double] = [0.9, 0.55, 0.25]
    
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Color.green.opacity(0.7), lineWidth: 3)
                    .frame(width: 140, height: 140)
                    .scaleEffect(frozen ? frozenScale[i] : (pulse ? 1.6 : 0.3))
                    .opacity(frozen ? frozenOpacity[i] : (pulse ? 0 : 0.9))
                    .animation(frozen ? nil : .easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(i) * 0.8), value: pulse)
            }
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.green)
        }
        .frame(width: 220, height: 220)
        .onAppear { if !frozen { pulse = true } }
        .accessibilityHidden(true)
    }
}

struct ContentView: View {
    @StateObject var ble = AdvancedBLEManager()
    @AppStorage("lastSavedMinutes") private var lastSavedMinutes: Int = 10
    @State private var newBoardName = ""
    @State private var showFirmware = ProcessInfo.processInfo.arguments.contains("-showFirmware")  // also used for screenshots
    @State private var showColors = ProcessInfo.processInfo.arguments.contains("-showColors")  // also used for screenshots
    @State private var showTutorial = ProcessInfo.processInfo.arguments.contains("-showTutorial")  // also used for screenshots
    
    private var hasBoards: Bool { !ble.discoveredDevices.isEmpty || !ble.demoBoardNames.isEmpty }
    
    private func boardRow(name: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(name).bold()
            Spacer()
            Button("Link Display", action: action).buttonStyle(.borderedProminent)
        }
    }
    
    func getOrdinalLabel(p: Int, total: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = Locale.current
        let ordinalStr = formatter.string(from: NSNumber(value: p)) ?? "\(p)"
        return String(localized: "\(ordinalStr) of \(total)")
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
                                boardRow(name: device.name ?? String(localized: "Unnamed Scoreboard")) { ble.connect(to: device) }
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
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showTutorial = true } label: { Image(systemName: "questionmark.circle") }
                                .accessibilityLabel(Text("Tutorial"))
                        }
                    }
                } else {
                    ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 20) {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Match Configuration").font(.caption).bold().foregroundColor(.secondary)
                                    Spacer()
                                    Text(LocalizedStringKey(ble.isSimulating ? "Simulator" : "Linked")).foregroundColor(ble.isSimulating ? .purple : .green).font(.caption2).bold()
                                    Button { showTutorial = true } label: { Image(systemName: "questionmark.circle") }
                                        .accessibilityLabel(Text("Tutorial"))
                                    Button(LocalizedStringKey(ble.isSimulating ? "Exit simulator" : "Disconnect")) { ble.disconnect() }.font(.caption2).bold().foregroundColor(.red).buttonStyle(.bordered).controlSize(.mini).tint(.red)
                                }
                                if let battery = ble.batteryPercent {
                                    HStack {
                                        Image(systemName: battery < 15 ? "battery.0percent" : (battery < 50 ? "battery.50percent" : "battery.100percent"))
                                            .foregroundColor(battery < 15 ? .red : (battery < 50 ? .orange : .green))
                                        Text("Battery \(battery)%").font(.caption).bold()
                                            .foregroundColor(battery < 15 ? .red : (battery < 50 ? .orange : .green))
                                        Spacer()
                                    }
                                }
                                if ble.boardFirmwareOutdated {
                                    Label("Board firmware is outdated. Update it to use all features.", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption2).foregroundColor(.orange)
                                }
                                HStack {
                                    Image(systemName: "clock.badge.checkmark").foregroundColor(.purple)
                                    Text("Unit Name:").font(.subheadline).bold()
                                    TextField("e.g. Period, Cuarto, Tiempo", text: $ble.periodLabelText).textFieldStyle(.roundedBorder).font(.subheadline)
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
                                }
                                Button { showColors = true } label: {
                                    HStack {
                                        Image(systemName: "paintpalette").foregroundColor(.pink)
                                        Text("Panel Colors").font(.subheadline).bold()
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
                            }
                            .padding().background(Color(.secondarySystemBackground)).cornerRadius(14).padding(.horizontal)
                            .onChange(of: ble.homeName) { ble.syncDataToDisplay() }
                            .onChange(of: ble.awayName) { ble.syncDataToDisplay() }
                            .onChange(of: ble.periodLabelText) { ble.syncDataToDisplay() }
                            
                            Text("\(getOrdinalLabel(p: ble.period, total: ble.totalPeriods)) \(ble.periodLabelText) Match")
                                .font(.title3).bold().foregroundColor(.purple).padding(.top, 5)
                            
                            HStack(spacing: 20) {
                                VStack {
                                    Text(ble.homeName.isEmpty ? String(localized: "HOME") : ble.homeName.uppercased()).bold().foregroundColor(.blue).lineLimit(1)
                                    Text("\(ble.homeScore)").font(.system(size: 55, weight: .black, design: .monospaced))
                                    Stepper("", value: $ble.homeScore, in: 0...99, onEditingChanged: { _ in ble.syncDataToDisplay() }).labelsHidden()
                                }.frame(maxWidth: .infinity).padding().background(Color(.secondarySystemBackground)).cornerRadius(12)
                                
                                VStack {
                                    Text(ble.awayName.isEmpty ? String(localized: "AWAY") : ble.awayName.uppercased()).bold().foregroundColor(.red).lineLimit(1)
                                    Text("\(ble.awayScore)").font(.system(size: 55, weight: .black, design: .monospaced))
                                    Stepper("", value: $ble.awayScore, in: 0...99, onEditingChanged: { _ in ble.syncDataToDisplay() }).labelsHidden()
                                }.frame(maxWidth: .infinity).padding().background(Color(.secondarySystemBackground)).cornerRadius(12)
                            }.padding(.horizontal)
                            
                            VStack(spacing: 12) {
                                Text("\(getOrdinalLabel(p: ble.period, total: ble.totalPeriods)) Countdown").font(.subheadline).foregroundColor(.secondary).bold()
                                Text(String(format: "%02d:%02d", ble.timerMin, ble.timerSec)).font(.system(size: 40, weight: .bold, design: .monospaced))
                                HStack(spacing: 15) {
                                    Button(LocalizedStringKey(ble.isTimerRunning ? "Pause" : "Start")) { ble.toggleClock() }.buttonStyle(.borderedProminent).tint(ble.isTimerRunning ? .orange : .green)
                                    Button("Reset Clock") { ble.resetClockManual(minutes: lastSavedMinutes) }.buttonStyle(.bordered)
                                    Stepper("Min", value: Binding(get: { ble.timerMin }, set: { newValue in ble.timerMin = newValue; lastSavedMinutes = newValue; ble.syncDataToDisplay() }), in: 1...90).labelsHidden()
                                }
                            }.padding().background(Color(.secondarySystemBackground)).cornerRadius(12).padding(.horizontal)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("\(ble.periodLabelText):").font(.subheadline).bold()
                                    Picker("", selection: $ble.period) {
                                        ForEach(1...ble.totalPeriods, id: \.self) { Text("\($0)").tag($0) }
                                    }.pickerStyle(.menu).onChange(of: ble.period) { ble.syncDataToDisplay() }
                                    Spacer()
                                    Text("Total:").font(.subheadline).bold()
                                    Picker("", selection: $ble.totalPeriods) {
                                        ForEach(1...9, id: \.self) { Text("\($0)").tag($0) }
                                    }.pickerStyle(.menu).onChange(of: ble.totalPeriods) {
                                        if ble.period > ble.totalPeriods { ble.period = ble.totalPeriods }
                                        ble.syncDataToDisplay()
                                    }
                                }
                                Divider()
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("LED Panel Brightness").font(.caption).bold()
                                        // 10...120 is the range the firmware accepts; show it as a percentage of the maximum
                                        Text("\(Int((ble.brightness / 120 * 100).rounded()))%")
                                            .font(.title3).bold().monospacedDigit()
                                    }
                                    Spacer()
                                    Stepper("LED Panel Brightness", value: $ble.brightness, in: 10...120, step: 5).labelsHidden()
                                }
                                .onChange(of: ble.brightness) { ble.syncDataToDisplay() }
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
                    .navigationDestination(isPresented: $showFirmware) { FirmwareUpdateView(ble: ble, updater: ble.firmwareUpdater) }
                    }
                }
            }
            
            // Tutorial sheet is attached below on the ZStack
            // FIXED: NATIVE IPHONE VISUAL ALERT OVERLAY HUD DISPLAY
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
    }
}
