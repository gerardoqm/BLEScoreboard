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
    @Published var periodLabelText = String(localized: "Period")
    @Published var alertText = ""
    @Published var showAlert = false

    static let maxScore = 99

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
    func nextPeriod() { period = period < totalPeriods ? period + 1 : 1; send(["p": period]) }
    func toggleRunning() { isRunning.toggle(); send(["r": isRunning]) }
    func reset() {
        homeScore = 0; awayScore = 0; period = 1; isRunning = false
        send(["h": 0, "a": 0, "p": 1, "r": false])
    }

    private func send(_ payload: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }

    // MARK: - WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Ask the phone for the current match state; it answers with a full update.
        if activationState == .activated { send(["sync": true]) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            // State pushed by the iPhone (scores, period, clock running, labels)
            if let h = message["h"] as? Int { self.homeScore = min(max(h, 0), Self.maxScore) }
            if let a = message["a"] as? Int { self.awayScore = min(max(a, 0), Self.maxScore) }
            if let t = message["t"] as? Int, t >= 1 { self.totalPeriods = t }
            if let p = message["p"] as? Int { self.period = min(max(p, 1), self.totalPeriods) }
            if let r = message["r"] as? Bool { self.isRunning = r }
            if let l = message["l"] as? String { self.periodLabelText = l }

            // Alerts from the iPhone: haptic for kickoff, period change and final whistle, plus a banner
            if let alertID = message["triggerAlert"] as? Int {
                switch alertID {
                case 1: WKInterfaceDevice.current().play(.click)
                case 2: WKInterfaceDevice.current().play(.notification)
                case 3: WKInterfaceDevice.current().play(.success)
                default: break
                }
            }
            if let text = message["alertText"] as? String, !text.isEmpty {
                self.alertText = text
                withAnimation { self.showAlert = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { self.showAlert = false } }
            }
        }
    }
}

// MARK: - Watch Control Interface Layout View
struct ContentView: View {
    @StateObject private var model = WatchModel()
    
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
    private func teamBlock(name: LocalizedStringKey, color: Color, score: Int,
                           change: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 3) {
            Text(name).font(.system(size: 10, weight: .bold)).foregroundColor(color)
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
        ZStack {
            ScrollView {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        teamBlock(name: "HOME", color: .blue, score: model.homeScore) { model.changeHome(by: $0) }
                        teamBlock(name: "AWAY", color: .red, score: model.awayScore) { model.changeAway(by: $0) }
                    }
                    
                    HStack(spacing: 6) {
                        // Period Cycle Selector Toggle
                        pill(tint: .gray, action: { model.nextPeriod() }) {
                            Text("PER: \(model.period)/\(model.totalPeriods)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.yellow)
                        }
                        
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
    }
}
