import ActivityKit
import Foundation

/// What the match Live Activity shows. The app and the widget extension both compile this file.
nonisolated struct MatchActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var homeName: String
        var awayName: String
        var homeScore: Int
        var awayScore: Int
        /// "2nd quarter", "1er tiempo"...
        var periodText: String
        /// Seconds on the clock when the state was sent: what a paused clock shows.
        var secondsLeft: Int
        /// When the clock reaches zero while it runs; the widget counts down to it by itself, no updates needed.
        var clockEnd: Date?
        var isRunning: Bool
    }
}
