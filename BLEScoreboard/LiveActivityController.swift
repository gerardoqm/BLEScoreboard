import ActivityKit
import Foundation

/// Keeps one match Live Activity on the lock screen, in the Dynamic Island and on the Apple Watch.
/// The countdown runs inside the widget, so it only needs an update when something changes: a score, the period, start or pause.
final class LiveActivityController {
    private var activity: Activity<MatchActivityAttributes>?
    private var lastState: MatchActivityAttributes.ContentState?
    
    var isActive: Bool { currentActivity() != nil }
    
    /// The activity that is really on screen: the one this run started, or one left by an earlier run. An activity the user swiped away,
    /// that the system ended, or that was ended elsewhere is forgotten, so a new one can be started.
    private func currentActivity() -> Activity<MatchActivityAttributes>? {
        if let activity, activity.activityState == .active || activity.activityState == .stale { return activity }
        activity = Activity<MatchActivityAttributes>.activities.first { $0.activityState == .active || $0.activityState == .stale }
        return activity
    }
    
    /// Shows `state`, starting the activity if there is none and `start` is true (iOS only lets an app start one while it is on screen).
    func show(_ state: MatchActivityAttributes.ContentState, start: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let existing = currentActivity()
        if existing != nil, state == lastState { return }
        let content = ActivityContent(state: state, staleDate: nil)
        if let existing {
            lastState = state
            Task { await existing.update(content) }
        } else if start {
            do {
                activity = try Activity.request(attributes: MatchActivityAttributes(), content: content, pushType: nil)
                lastState = state
            } catch {
                lastState = nil          // try again at the next change (for example when the app is on screen)
                print("[liveactivity] could not start: \(error)")
            }
        }
    }
    
    /// Takes every match activity off the lock screen.
    func end() {
        let running = Activity<MatchActivityAttributes>.activities
        activity = nil
        lastState = nil
        guard !running.isEmpty else { return }
        Task { for item in running { await item.end(nil, dismissalPolicy: .immediate) } }
    }
}
