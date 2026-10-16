import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @StateObject var ble = AdvancedBLEManager()
    @AppStorage("lastSavedMinutes") private var lastSavedMinutes: Int = 10
    @State private var newBoardName = ""
    
    func getOrdinalLabel(p: Int, total: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = Locale.current
        let ordinalStr = formatter.string(from: NSNumber(value: p)) ?? "\(p)"
        return "\(ordinalStr) of \(total)"
    }
    
    var body: some View {
        ZStack { // Enclosed within ZStack to project overlays
            NavigationStack {
                if !ble.isConnected {
                    VStack {
                        Text("Select Your Scoreboard").font(.title2).bold().padding(.top)
                        Text("Select your board to avoid interference.").font(.caption).foregroundColor(.secondary)
                        List(ble.discoveredDevices, id: \.identifier) { device in
                            HStack {
                                Text(device.name ?? "Unnamed Scoreboard").bold()
                                Spacer()
                                Button("Link Display") { ble.connect(to: device) }.buttonStyle(.borderedProminent)
                            }
                        }.refreshable { ble.startScanning() }
                    }.navigationTitle("Radar Scanner")
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Match Configuration").font(.caption).bold().foregroundColor(.secondary)
                                    Spacer()
                                    Text("Linked").foregroundColor(.green).font(.caption2).bold()
                                }
                                HStack {
                                    Image(systemName: "clock.badge.checkmark").foregroundColor(.purple)
                                    Text("Unit Name:").font(.subheadline).bold()
                                    TextField("e.g. Period, Cuarto, Tiempo", text: $ble.periodLabelText).textFieldStyle(.roundedBorder).font(.subheadline)
                                }
                                HStack {
                                    Image(systemName: "pencil.circle").foregroundColor(.orange)
                                    Text("Board Name:").font(.subheadline).bold()
                                    TextField(ble.connectedPeripheral?.name ?? "Scoreboard", text: $newBoardName)
                                        .textFieldStyle(.roundedBorder).font(.subheadline)
                                        .onChange(of: newBoardName) { ble.renameStatus = "" }
                                    Button("Rename") { ble.renameDevice(to: newBoardName) }
                                        .buttonStyle(.bordered)
                                        .disabled(newBoardName.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                                if !ble.renameStatus.isEmpty {
                                    Text(ble.renameStatus).font(.caption2).foregroundColor(.secondary)
                                }
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
                                    Text(ble.homeName.isEmpty ? "HOME" : ble.homeName.uppercased()).bold().foregroundColor(.blue).lineLimit(1)
                                    Text("\(ble.homeScore)").font(.system(size: 55, weight: .black, design: .monospaced))
                                    Stepper("", value: $ble.homeScore, in: 0...99, onEditingChanged: { _ in ble.syncDataToDisplay() }).labelsHidden()
                                }.frame(maxWidth: .infinity).padding().background(Color(.secondarySystemBackground)).cornerRadius(12)
                                
                                VStack {
                                    Text(ble.awayName.isEmpty ? "AWAY" : ble.awayName.uppercased()).bold().foregroundColor(.red).lineLimit(1)
                                    Text("\(ble.awayScore)").font(.system(size: 55, weight: .black, design: .monospaced))
                                    Stepper("", value: $ble.awayScore, in: 0...99, onEditingChanged: { _ in ble.syncDataToDisplay() }).labelsHidden()
                                }.frame(maxWidth: .infinity).padding().background(Color(.secondarySystemBackground)).cornerRadius(12)
                            }.padding(.horizontal)
                            
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
                                Text("LED Panel Brightness").font(.caption).bold()
                                Slider(value: $ble.brightness, in: 10...120, step: 5) { _ in ble.syncDataToDisplay() }
                            }.padding().background(Color(.secondarySystemBackground)).cornerRadius(12).padding(.horizontal)
                            
                            VStack(spacing: 12) {
                                Text(getOrdinalLabel(p: ble.period, total: ble.totalPeriods) + " Countdown").font(.subheadline).foregroundColor(.secondary).bold()
                                Text(String(format: "%02d:%02d", ble.timerMin, ble.timerSec)).font(.system(size: 40, weight: .bold, design: .monospaced))
                                HStack(spacing: 15) {
                                    Button(ble.isTimerRunning ? "Pause" : "Start") { ble.toggleClock() }.buttonStyle(.borderedProminent).tint(ble.isTimerRunning ? .orange : .green)
                                    Button("Reset Clock") { ble.resetClockManual(minutes: lastSavedMinutes) }.buttonStyle(.bordered)
                                    Stepper("Min", value: Binding(get: { ble.timerMin }, set: { newValue in ble.timerMin = newValue; lastSavedMinutes = newValue; ble.syncDataToDisplay() }), in: 1...90).labelsHidden()
                                }
                            }.padding().background(Color(.secondarySystemBackground)).cornerRadius(12).padding(.horizontal)
                            
                            Button("Disconnect Board Casing") { ble.disconnect() }.font(.footnote).foregroundColor(.red).padding(.top, 10)
                        }.padding(.top)
                    }
                    .onAppear { ble.timerMin = lastSavedMinutes }
                }
            }
            
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
    }
}
