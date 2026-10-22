import SwiftUI

/// The match screen when the phone is turned sideways: the simulated LED panel fills the screen, with the controls in one row below.
/// It makes the phone usable as the scoreboard itself if the real panel does not work.
struct LandscapeScoreboardView: View {
    @ObservedObject var ble: AdvancedBLEManager
    @AppStorage("lastSavedMinutes") private var lastSavedMinutes: Int = 10

    private func scoreControls(_ title: LocalizedStringKey, color: Color, score: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Button { score.wrappedValue = max(score.wrappedValue - 1, 0); ble.syncDataToDisplay() } label: { Image(systemName: "minus") }
                .accessibilityLabel(Text("Minus"))
                .disabled(score.wrappedValue <= 0)
            Text(title).font(.caption).bold().foregroundColor(color).lineLimit(1)
            Button { score.wrappedValue = min(score.wrappedValue + 1, 99); ble.syncDataToDisplay() } label: { Image(systemName: "plus") }
                .accessibilityLabel(Text("Plus"))
                .disabled(score.wrappedValue >= 99)
        }
        .buttonStyle(.bordered).controlSize(.small).tint(color)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            scoreControls("HOME", color: .blue, score: $ble.homeScore)
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                Button { ble.changePeriod(by: -1) } label: { Image(systemName: "backward.end.fill") }
                    .accessibilityLabel(Text("Previous period"))
                    .disabled(ble.period <= 1)
                Text("\(ble.periodLabelText) \(ble.period)/\(ble.totalPeriods)").font(.caption).bold().foregroundColor(.yellow).lineLimit(1)
                Button { ble.changePeriod(by: 1) } label: { Image(systemName: "forward.end.fill") }
                    .accessibilityLabel(Text("Next period"))
                    .disabled(ble.period >= ble.totalPeriods)
                Button { ble.toggleClock() } label: {
                    Label(LocalizedStringKey(ble.isTimerRunning ? "Pause" : "Start"), systemImage: ble.isTimerRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent).tint(ble.isTimerRunning ? .orange : .green)
                Button { ble.resetClockManual(minutes: lastSavedMinutes) } label: { Image(systemName: "arrow.counterclockwise") }
                    .accessibilityLabel(Text("Reset Clock"))
            }
            .buttonStyle(.bordered).controlSize(.small)
            Spacer(minLength: 4)
            scoreControls("AWAY", color: .red, score: $ble.awayScore)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            LiveBoardPreview(ble: ble)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            controls
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }       // the screen stays on while it is the scoreboard
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
