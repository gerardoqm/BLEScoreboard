import SwiftUI
import Combine

/// What the app can announce during a match.
enum AlertEvent: String, CaseIterable, Identifiable {
    case goal, timeLeft, matchStart, periodStart, periodEnd, halfTime, matchEnd

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .goal: return "Goal"
        case .timeLeft: return "Time left"
        case .matchStart: return "Match start"
        case .periodStart: return "Period start"
        case .periodEnd: return "Period end"
        case .halfTime: return "Half time"
        case .matchEnd: return "Match end"
        }
    }
}

/// How one event is announced: spoken or played (audio), on the app banner, on the panel.
struct AlertChannels: Codable, Equatable {
    var audio = true
    var banner = true
    var panel = true
}

/// The alert settings screen's data, saved on the phone.
final class AlertSettings: ObservableObject {
    static let availableMinutes = Array(1...15)
    private static let storeKey = "alertSettings"

    private struct Stored: Codable {
        var audioEnabled: Bool
        var channels: [String: AlertChannels]
        var timeLeftMinutes: [Int]
        var liveActivityEnabled: Bool?      // added later: older saved settings do not have it
        var voiceIdentifier: String?
        var goalWord: String?               // added later
        var tickerEnabled: Bool?
    }

    /// Master switch for everything spoken or played.
    @Published var audioEnabled = true { didSet { save() } }
    @Published private var channels: [String: AlertChannels] = [:] { didSet { save() } }
    /// The match on the lock screen, in the Dynamic Island and on the watch.
    @Published var liveActivityEnabled = true { didSet { save() } }
    /// The voice used for spoken announcements ("" = the best one installed).
    @Published var voiceIdentifier = "" { didSet { save() } }
    /// The word of the goal alert ("Touchdown", "Home run"...); empty = "Goal" / "Gol".
    @Published var goalWord = "" { didSet { save() } }
    /// Hundredths of a second next to the clock in the last minute of a period.
    @Published var tickerEnabled = true { didSet { save() } }
    /// Minutes before the end of a period at which the time left is announced.
    @Published var timeLeftMinutes: Set<Int> = [5, 3, 1] { didSet { save() } }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            audioEnabled = stored.audioEnabled
            channels = stored.channels
            timeLeftMinutes = Set(stored.timeLeftMinutes)
            liveActivityEnabled = stored.liveActivityEnabled ?? true
            voiceIdentifier = stored.voiceIdentifier ?? ""
            goalWord = stored.goalWord ?? ""
            tickerEnabled = stored.tickerEnabled ?? true
        }
    }

    func channels(for event: AlertEvent) -> AlertChannels { channels[event.rawValue] ?? AlertChannels() }

    func binding(_ event: AlertEvent, _ keyPath: WritableKeyPath<AlertChannels, Bool>) -> Binding<Bool> {
        Binding(get: { self.channels(for: event)[keyPath: keyPath] },
                set: { value in var c = self.channels(for: event); c[keyPath: keyPath] = value; self.channels[event.rawValue] = c })
    }

    func binding(minutes: Int) -> Binding<Bool> {
        Binding(get: { self.timeLeftMinutes.contains(minutes) },
                set: { if $0 { self.timeLeftMinutes.insert(minutes) } else { self.timeLeftMinutes.remove(minutes) } })
    }

    private func save() {
        let stored = Stored(audioEnabled: audioEnabled, channels: channels, timeLeftMinutes: timeLeftMinutes.sorted(), liveActivityEnabled: liveActivityEnabled, voiceIdentifier: voiceIdentifier, goalWord: goalWord, tickerEnabled: tickerEnabled)
        UserDefaults.standard.set(voiceIdentifier, forKey: AudioAnnouncer.voiceKey)      // read by the announcer
        if let data = try? JSONEncoder().encode(stored) { UserDefaults.standard.set(data, forKey: Self.storeKey) }
    }
}
