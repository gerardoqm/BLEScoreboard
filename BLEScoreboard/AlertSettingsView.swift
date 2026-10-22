import AVFoundation
import SwiftUI

/// Page for choosing how each event is announced: spoken or played, on the app banner, on the panel.
struct AlertSettingsView: View {
    @ObservedObject var ble: AdvancedBLEManager
    @ObservedObject var alerts: AlertSettings
    private let voices = AudioAnnouncer.voices()
    
    private func qualityName(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return String(localized: "Premium")
        case .enhanced: return String(localized: "Enhanced")
        default: return String(localized: "Standard")
        }
    }

    private func switchColumn(_ binding: Binding<Bool>, available: Bool = true) -> some View {
        Toggle("", isOn: binding).labelsHidden().scaleEffect(0.8).frame(width: 58)
            .disabled(!available).opacity(available ? 1 : 0.25)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $alerts.liveActivityEnabled) {
                        Label("Live Activity", systemImage: "platter.filled.top.iphone").font(.subheadline).bold()
                    }
                    Text("Shows the scores, period and countdown on the lock screen and in the Dynamic Island, and on your Apple Watch, so you can switch apps or take a call without losing the match.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding().background(Color(.secondarySystemBackground)).cornerRadius(12)
                .onChange(of: alerts.liveActivityEnabled) { ble.updateLiveActivity() }
                
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $alerts.audioEnabled) {
                        Label("Audio announcements", systemImage: "speaker.wave.2.fill").font(.subheadline).bold()
                    }
                    Divider()
                    HStack {
                        Label("Speaker", systemImage: "hifispeaker").font(.subheadline).bold()
                        Spacer()
                        RoutePickerView().frame(width: 36, height: 36)
                    }
                    Text("Pair your Bluetooth speaker in Settings, then choose it here. Audio is spoken in the app's language; whistles and horns mark the start and end of periods and of the match.")
                        .font(.caption).foregroundColor(.secondary)
                    Divider()
                    HStack(spacing: 8) {
                        Label("Voice", systemImage: "waveform").font(.subheadline).bold()
                        Spacer(minLength: 8)
                        Picker("Voice", selection: $alerts.voiceIdentifier) {
                            Text("Automatic").tag("")
                            ForEach(voices, id: \.identifier) { voice in
                                Text("\(voice.name) · \(qualityName(voice))").tag(voice.identifier)
                            }
                        }
                        .pickerStyle(.menu)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)      // the voice name stays on one line
                        Button { AudioAnnouncer.shared.speak(ble.timeLeftPhrase(5)) } label: { Image(systemName: "play.circle").font(.title3) }
                            .accessibilityLabel(Text("Hear it"))
                    }
                    Text("For a more natural voice, download an Enhanced or Premium one in Settings > Accessibility > Spoken Content > Voices. It shows up here, and Automatic picks the best one installed.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding().background(Color(.secondarySystemBackground)).cornerRadius(12)

                VStack(alignment: .leading, spacing: 8) {
                    Grid(alignment: .center, horizontalSpacing: 4, verticalSpacing: 10) {
                        GridRow {
                            Text("").gridColumnAlignment(.leading)
                            Text("Audio").font(.caption2).bold().foregroundColor(.secondary)
                            Text("Banner").font(.caption2).bold().foregroundColor(.secondary)
                            Text("Panel").font(.caption2).bold().foregroundColor(.secondary)
                            Text("")
                        }
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(AlertEvent.allCases) { event in
                            GridRow {
                                Text(event.title).font(.subheadline).bold().gridColumnAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                switchColumn(alerts.binding(event, \.audio), available: alerts.audioEnabled)
                                switchColumn(alerts.binding(event, \.banner))
                                switchColumn(alerts.binding(event, \.panel))
                                Button { ble.testAlert(event) } label: { Image(systemName: "play.circle").font(.title3) }
                                    .accessibilityLabel(Text("Test"))
                            }
                        }
                    }
                    Text("Banner shows on the phone (and vibrates the watch); Panel shows on the board. The play button tries an event.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding().background(Color(.secondarySystemBackground)).cornerRadius(12)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Announce the time left at").font(.subheadline).bold()
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(AlertSettings.availableMinutes, id: \.self) { minutes in
                            Toggle(isOn: alerts.binding(minutes: minutes)) {
                                Text("\(minutes)").font(.subheadline).bold().frame(maxWidth: .infinity)
                            }
                            .toggleStyle(.button)
                        }
                    }
                    Text("Minutes before the end of the period.").font(.caption).foregroundColor(.secondary)
                    Text("Only times shorter than the period are announced, once each, as the clock passes them.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding().background(Color(.secondarySystemBackground)).cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Alerts and Sound")
        .navigationBarTitleDisplayMode(.inline)
    }
}
