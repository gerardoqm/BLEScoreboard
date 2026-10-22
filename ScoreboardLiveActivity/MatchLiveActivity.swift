import ActivityKit
import SwiftUI
import WidgetKit

/// The match on the lock screen and in the Dynamic Island: scores, period and the countdown.
/// iOS also shows it on a paired Apple Watch.
struct MatchLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MatchActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TeamView(name: state.homeName, score: state.homeScore, color: .blue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TeamView(name: state.awayName, score: state.awayScore, color: .red)
                }
                DynamicIslandExpandedRegion(.center) {
                    ClockView(state: state, size: 30)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(state.periodText).font(.footnote).foregroundStyle(.yellow)
                }
            } compactLeading: {
                Text("\(state.homeScore) - \(state.awayScore)").font(.caption).bold().monospacedDigit()
            } compactTrailing: {
                ClockView(state: state, size: 13).frame(width: 46)
            } minimal: {
                ClockView(state: state, size: 11).frame(width: 40)
            }
        }
    }
}

/// The countdown: counts down by itself while the clock runs, and shows the frozen time while it is paused.
private struct ClockView: View {
    let state: MatchActivityAttributes.ContentState
    let size: CGFloat
    
    var body: some View {
        Group {
            if state.isRunning, let end = state.clockEnd, end > Date() {
                Text(timerInterval: Date()...end, countsDown: true, showsHours: false)
            } else {
                Text(String(format: "%02d:%02d", state.secondsLeft / 60, state.secondsLeft % 60))
            }
        }
        .font(.system(size: size, weight: .bold, design: .monospaced))
        .foregroundStyle(state.isRunning ? Color.green : Color.orange)
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

private struct TeamView: View {
    let name: String
    let score: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(name.uppercased()).font(.caption2).bold().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text("\(score)").font(.system(size: 34, weight: .black, design: .rounded)).monospacedDigit()
        }
        .frame(minWidth: 60)
    }
}

private struct LockScreenView: View {
    let state: MatchActivityAttributes.ContentState
    
    var body: some View {
        HStack {
            TeamView(name: state.homeName, score: state.homeScore, color: .blue)
            Spacer()
            VStack(spacing: 4) {
                ClockView(state: state, size: 38)
                Text(state.periodText).font(.footnote).bold().foregroundStyle(.yellow)
            }
            Spacer()
            TeamView(name: state.awayName, score: state.awayScore, color: .red)
        }
        .foregroundStyle(.white)
    }
}
