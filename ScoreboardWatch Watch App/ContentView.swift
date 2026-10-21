//
//  ContentView.swift
//  ScoreboardWatch Watch App
//
//  Created by Gerardo Quintanar Morales on 15/10/26.
//

import SwiftUI
import Combine
import WatchConnectivity
import WatchKit

/// Watch-side copy of the match state. The iPhone app owns the clock and the Bluetooth link;
/// the watch follows its updates and sends back only the value the user just changed.
final class WatchModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var homeScore = 0
    @Published var awayScore = 0
    @Published var period = 1
    @Published var totalPeriods = 4
    @Published var isRunning = false
    @Published var language = AppLanguage.current
    @Published var homeName = ""
    @Published var awayName = ""
    @Published var minutes = 10
    @Published var seconds = 0
    @Published var periodLabelText = tr("Period")
    @Published var alertText = ""
    @Published var showAlert = false

    static let maxScore = 99
    /// The phone sends the clock about once a second; between messages (screen off, link busy) the watch keeps counting itself.
    private var clockTimer: Timer?

    override init() {
        super.init()
        // Sample state for tutorial screenshots in the simulator (`-demo`).
        if ProcessInfo.processInfo.arguments.contains("-demo") { homeScore = 12; awayScore = 9; period = 2 }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: - Actions (each sends only the keys it changed, so a stale value can't overwrite the phone)
    func changeHome(by delta: Int) { homeScore = min(max(homeScore + delta, 0), Self.maxScore); send(["h": homeScore]) }
    func changeAway(by delta: Int) { awayScore = min(max(awayScore + delta, 0), Self.maxScore); send(["a": awayScore]) }
    /// A new period stops the clock; the phone answers with the full next period ready to start.
    func changePeriod(by delta: Int) {
        let target = min(max(period + delta, 1), totalPeriods)
        guard target != period else { return }
        period = target; isRunning = false; updateClockTimer()
        send(["p": period])
    }
    func toggleRunning() { isRunning.toggle(); updateClockTimer(); send(["r": isRunning]) }
    func reset() {
        homeScore = 0; awayScore = 0; period = 1; isRunning = false; updateClockTimer()
        send(["h": 0, "a": 0, "p": 1, "r": false, "rc": true])
    }

    private func updateClockTimer() {
        clockTimer?.invalidate(); clockTimer = nil
        guard isRunning else { return }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.isRunning else { return }
            if self.seconds > 0 { self.seconds -= 1 }
            else if self.minutes > 0 { self.minutes -= 1; self.seconds = 59 }
        }
    }
    
    /// Ask the phone for the current state, e.g. when the watch app comes to the foreground.
    func requestSync() { send(["sync": true]) }

    private func send(_ payload: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }

    // MARK: - WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        // Use the last state the phone stored while the watch was asleep, then ask for a fresh one.
        let stored = session.receivedApplicationContext
        if !stored.isEmpty { DispatchQueue.main.async { self.apply(stored) } }
        send(["sync": true])
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { self.apply(applicationContext) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { self.apply(message) }
    }

    private func apply(_ message: [String: Any]) {
        // State pushed by the iPhone (scores, period, clock, labels)
        if let h = message["h"] as? Int { homeScore = min(max(h, 0), Self.maxScore) }
        if let a = message["a"] as? Int { awayScore = min(max(a, 0), Self.maxScore) }
        if let t = message["t"] as? Int, t >= 1 { totalPeriods = t }
        if let p = message["p"] as? Int { period = min(max(p, 1), totalPeriods) }
        if let r = message["r"] as? Bool { isRunning = r }
        if let l = message["l"] as? String { periodLabelText = l }
        if let code = message["lang"] as? String {                      // language picked in the iPhone app
            let picked = AppLanguage(rawValue: code) ?? .system
            if picked != language { language = picked; UserDefaults.standard.set(picked.rawValue, forKey: AppLanguage.storeKey) }
        }
        if let n = message["hn"] as? String { homeName = n.trimmingCharacters(in: .whitespaces) }
        if let n = message["an"] as? String { awayName = n.trimmingCharacters(in: .whitespaces) }
        if let m = message["m"] as? Int, let sec = message["s"] as? Int {
            var total = min(max(m, 0), 99) * 60 + min(max(sec, 0), 59)
            // A state that arrived late (watch was asleep): take off the time that passed since the phone sent it.
            if isRunning, let sent = message["ts"] as? Double { total = max(0, total - max(0, Int(Date().timeIntervalSince1970 - sent))) }
            minutes = total / 60; seconds = total % 60
        }
        updateClockTimer()

        // Alerts from the iPhone: haptic for kickoff, period change and final whistle, plus a banner
        if let alertID = message["triggerAlert"] as? Int {
            switch alertID {
            case 1: WKInterfaceDevice.current().play(.click)
            case 2: WKInterfaceDevice.current().play(.notification)
            case 3: WKInterfaceDevice.current().play(.success)
            case 4: WKInterfaceDevice.current().play(.notification)   // half time
            case 5: WKInterfaceDevice.current().play(.success)        // goal
            default: break
            }
        }
        if let text = message["alertText"] as? String, !text.isEmpty {
            alertText = text
            withAnimation { showAlert = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { self.showAlert = false } }
        }
    }
}

// MARK: - Watch Control Interface Layout View
struct ContentView: View {
    @StateObject private var model = WatchModel()
    @Environment(\.scenePhase) private var scenePhase
    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
    
    /// Compact capsule button so the whole screen fits on the watch without scrolling.
    private func pill<Label: View>(tint: Color, filled: Bool = false, height: CGFloat = 32,
                                   action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity, minHeight: height)
                .background(filled ? tint : tint.opacity(0.28), in: Capsule())
        }
        .buttonStyle(.plain)
    }
    
    /// One team: name, score and - / + buttons.
    private func teamBlock(name: String, color: Color, score: Int,
                           change: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 3) {
            Text(name).font(.system(size: 10, weight: .bold)).foregroundColor(color).lineLimit(1).minimumScaleFactor(0.6)
            Text("\(score)").font(.title2).bold().foregroundColor(.white)
            HStack(spacing: 4) {
                pill(tint: color, height: 30, action: { change(-1) }) {
                    Image(systemName: "minus").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                }
                .opacity(score <= 0 ? 0.4 : 1).disabled(score <= 0)
                pill(tint: color, filled: true, height: 30, action: { change(1) }) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                }
                .opacity(score >= WatchModel.maxScore ? 0.4 : 1).disabled(score >= WatchModel.maxScore)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.15))
        .cornerRadius(14)
    }
    
    var body: some View {
        NavigationStack {
        ZStack {
            ScrollView {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        teamBlock(name: model.homeName.isEmpty ? tr("HOME") : model.homeName.uppercased(), color: .blue, score: model.homeScore) { model.changeHome(by: $0) }
                        teamBlock(name: model.awayName.isEmpty ? tr("AWAY") : model.awayName.uppercased(), color: .red, score: model.awayScore) { model.changeAway(by: $0) }
                    }
                    
                    HStack(spacing: 6) {
                        // Period Cycle Selector Toggle
                        // Previous (1/3) and next (2/3) period share the space the single period button had.
                        GeometryReader { geo in
                            let gap: CGFloat = 3
                            let unit = (geo.size.width - gap) / 3
                            HStack(spacing: gap) {
                                pill(tint: .gray, action: { model.changePeriod(by: -1) }) {
                                    Image(systemName: "backward.end.fill").font(.system(size: 11, weight: .semibold)).foregroundColor(.yellow)
                                }
                                .frame(width: unit)
                                .opacity(model.period <= 1 ? 0.4 : 1).disabled(model.period <= 1)
                                .accessibilityLabel(Text("Previous period"))
                                pill(tint: .gray, action: { model.changePeriod(by: 1) }) {
                                    Image(systemName: "forward.end.fill").font(.system(size: 12, weight: .semibold)).foregroundColor(.yellow)
                                }
                                .frame(width: unit * 2)
                                .opacity(model.period >= model.totalPeriods ? 0.4 : 1).disabled(model.period >= model.totalPeriods)
                                .accessibilityLabel(Text("Next period"))
                            }
                        }
                        .frame(height: 32)
                        
                        // Timer Start / Pause Switch Flag
                        pill(tint: .gray, action: { model.toggleRunning() }) {
                            Text(LocalizedStringKey(model.isRunning ? "PAUSE" : "START"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(model.isRunning ? .orange : .green)
                        }
                    }
                    
                    // Match Zero-Reset
                    pill(tint: .gray, height: 26, action: { model.reset() }) {
                        Text("Reset Values").font(.caption2).foregroundColor(.secondary)
                    }
                    
                    // App version (same number as the iPhone app, from the Xcode project)
                    Text("v\(Self.versionText)").font(.system(size: 9)).foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
            }
            // Banner for period start / match end alerts sent by the iPhone
            if model.showAlert {
                VStack {
                    Text(model.alertText)
                        .font(.caption2).bold()
                        .multilineTextAlignment(.center)
                        .padding(8)
                        .background(Color.purple.cornerRadius(8))
                        .shadow(radius: 4)
                    Spacer()
                }
                .transition(.move(edge: .top))
            }
        }
        // Countdown and period in the empty top-left corner, next to the system clock.
        // Countdown: green while running, orange while stopped (same colors as the panel).
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 5) {
                    Text(String(format: "%02d:%02d", model.minutes, model.seconds))
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundColor(model.isRunning ? .green : .orange)
                    Text("\(model.period)/\(model.totalPeriods)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.yellow)
                }
            }
        }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.requestSync() } }
        .environment(\.locale, model.language.locale)
    }
}
