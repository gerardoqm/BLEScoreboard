import SwiftUI
import CoreBluetooth
import SwiftUI

struct ContentView: View {
    @StateObject var ble = AdvancedBLEManager()
    @AppStorage("lastSavedMinutes") private var lastSavedMinutes: Int = 10
    
    // Apple Core Foundation Native Ordinal Localizer Converter Engine
    func getLocalizedOrdinal(value: Int, label: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = Locale.current
        
        let ordinalSuffixString = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(ordinalSuffixString) \(label)"
    }
    
    var body: some View {
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
                        
                        // SECTION 1: UPGRADED MATCH SETUP HEADINGS CARD (CUSTOMIZABLE)
                        VStack(spacing: 12) {
                            HStack {
                                Text("Match Configuration").font(.caption).bold().foregroundColor(.secondary)
                                Spacer()
                                Text("Linked: \(ble.connectedPeripheral?.name ?? "Display")")
                                    .foregroundColor(.green).font(.caption2).bold()
                            }
                            
                            // Custom Structural Match Unit Naming Field
                            HStack {
                                Image(systemName: "clock.badge.checkmark")
                                    .foregroundColor(.purple).font(.body)
                                Text("Unit Name:").font(.subheadline).bold()
                                TextField("e.g. Period, Cuarto, Tiempo, Half", text: $ble.periodLabelText)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.subheadline)
                            }
                            
                            Divider()
                            
                            // Custom Team Identity Text Input Fields
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Home Team").font(.caption2).bold().foregroundColor(.blue)
                                    TextField("REDS", text: $ble.homeName)
                                        .textFieldStyle(.roundedBorder)
                                        .multilineTextAlignment(.center)
                                }
                                
                                Text("VS")
                                    .font(.caption).bold()
                                    .padding(.top, 15)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Away Team").font(.caption2).bold().foregroundColor(.red)
                                    TextField("BLUES", text: $ble.awayName)
                                        .textFieldStyle(.roundedBorder)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(14)
                        .padding(.horizontal)
                        // Trigger real-time BLE synchronization changes down to the P4 panel instantly on typing
                        .onChange(of: ble.homeName) { _ in ble.syncDataToDisplay() }
                        .onChange(of: ble.awayName) { _ in ble.syncDataToDisplay() }
                        .onChange(of: ble.periodLabelText) { _ in ble.syncDataToDisplay() }
                        
                        // Dynamic Localized Header Tracker Readout Display Row
                        Text(getLocalizedOrdinal(value: ble.period, label: ble.periodLabelText))
                            .font(.title3).bold().foregroundColor(.purple)
                            .padding(.top, 5)
                        
                        // SECTION 2: NUMERIC SCORE CONTROL GRID
                        HStack(spacing: 20) {
                            VStack {
                                Text(ble.homeName.isEmpty ? "HOME" : ble.homeName.uppercased())
                                    .bold().foregroundColor(.blue).lineLimit(1)
                                Text("\(ble.homeScore)").font(.system(size: 55, weight: .black, design: .monospaced))
                                Stepper("", value: $ble.homeScore, in: 0...99, onEditingChanged: { _ in ble.syncDataToDisplay() }).labelsHidden()
                            }.frame(maxWidth: .infinity).padding().background(Color(.secondarySystemBackground)).cornerRadius(12)
                            
                            VStack {
                                Text(ble.awayName.isEmpty ? "AWAY" : ble.awayName.uppercased())
                                    .bold().foregroundColor(.red).lineLimit(1)
                                Text("\(ble.awayScore)").font(.system(size: 55, weight: .black, design: .monospaced))
                                Stepper("", value: $ble.awayScore, in: 0...99, onEditingChanged: { _ in ble.syncDataToDisplay() }).labelsHidden()
                            }.frame(maxWidth: .infinity).padding().background(Color(.secondarySystemBackground)).cornerRadius(12)
                        }.padding(.horizontal)
                        
                        // SECTION 3: PERIOD SELECTORS & BRIGHTNESS CONTROL BLOCK
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("\(ble.periodLabelText):").font(.subheadline).bold()
                                Picker("", selection: $ble.period) {
                                    ForEach(1...ble.totalPeriods, id: \.self) { Text("\($0)").tag($0) }
                                }.pickerStyle(.menu).onChange(of: ble.period) { _ in ble.syncDataToDisplay() }
                                
                                Spacer()
                                
                                Text("Total:").font(.subheadline).bold()
                                Picker("", selection: $ble.totalPeriods) {
                                    ForEach(1...9, id: \.self) { Text("\($0)").tag($0) }
                                }.pickerStyle(.menu).onChange(of: ble.totalPeriods) { _ in
                                    if ble.period > ble.totalPeriods { ble.period = ble.totalPeriods }
                                    ble.syncDataToDisplay()
                                }
                            }
                            Divider()
                            Text("LED Panel Brightness").font(.caption).bold()
                            Slider(value: $ble.brightness, in: 10...120, step: 5) { _ in ble.syncDataToDisplay() }
                        }.padding().background(Color(.secondarySystemBackground)).cornerRadius(12).padding(.horizontal)
                        
                        // SECTION 4: MATCH GAME COUNTDOWN TICKING CLOCK
                        VStack(spacing: 12) {
                            Text(getLocalizedOrdinal(value: ble.period, label: ble.periodLabelText) + " Countdown")
                                .font(.subheadline).foregroundColor(.secondary).bold()
                            
                            Text(String(format: "%02d:%02d", ble.timerMin, ble.timerSec)).font(.system(size: 40, weight: .bold, design: .monospaced))
                            
                            HStack(spacing: 15) {
                               // Calls on the robust toggle method
                               Button(ble.isTimerRunning ? "Pause" : "Start") {
                                   ble.toggleClock()
                               }
                               .buttonStyle(.borderedProminent)
                               .tint(ble.isTimerRunning ? .orange : .green)
                               
                               // Calls on the unified reset wrapper
                               Button("Reset Clock") {
                                   ble.resetClockManual(minutes: lastSavedMinutes)
                               }.buttonStyle(.bordered)
                               
                               Stepper("Min", value: Binding(get: { ble.timerMin }, set: { newValue in ble.timerMin = newValue; lastSavedMinutes = newValue; ble.syncDataToDisplay() }), in: 1...90).labelsHidden()
                            }                        }.padding().background(Color(.secondarySystemBackground)).cornerRadius(12).padding(.horizontal)

                        // Clean Disconnect Button Row Layout Placement
                        Button("Disconnect Discovered Board") { ble.disconnect() }
                            .font(.footnote).foregroundColor(.red).padding(.top, 10)
                        
                    }.padding(.top)
                }
                .onAppear { ble.timerMin = lastSavedMinutes }
            }
        }
    }
}
