//
//  ContentView.swift
//  ScoreboardWatch Watch App
//
//  Created by Gerardo Quintanar Morales on 15/10/26.
//

import SwiftUI
import WatchConnectivity
import WatchKit

class WatchSessionDelegate: NSObject, WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    
    // Captures the background alert payload string signals forwarded from your iPhone
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let alertID = message["triggerAlert"] as? Int {
            DispatchQueue.main.async {
                switch alertID {
                case 1:
                    // Digital Click Tap for kickoff/start
                    WKInterfaceDevice.current().play(.click)
                case 2:
                    // Distinct long notification chime/vibration for intermission
                    WKInterfaceDevice.current().play(.notification)
                case 3:
                    // Loud, prolonged Alarm tone vibration mimicking the final match whistle
                    WKInterfaceDevice.current().play(.success)
                default:
                    break
                }
            }
        }
        if let alertText = message["alertText"] as? String {
                DispatchQueue.main.async {
                    // Accessing global view bindings directly can break scope rules inside un-mapped delegates.
                    // Instead, pass the alert trigger downstream over a global Notification Center posting or write into a shared view controller model if preferred.
                }
            }
        
    }
}
// MARK: - Watch Control Interface Layout View
struct ContentView: View {
    @State private var homeScore = 0
    @State private var awayScore = 0
    @State private var period = 1
    @State private var totalPeriods = 4
    @State private var isRunning = false
    @State private var periodLabelText = "Period"
    @State private var sessionDelegate = WatchSessionDelegate()
    @State private var watchAlertText = ""
    @State private var showWatchAlert = false

    // Transmits messages instantly down to the linked iPhone background receiver
    func pushToPhone() {
        guard WCSession.default.activationState == .activated else {
            print("Sync Error: Watch Session Not Active")
            return
        }
        let payload: [String: Any] = [
            "h": homeScore,
            "a": awayScore,
            "p": period,
            "r": isRunning,
            "t": totalPeriods,
            "l": periodLabelText
        ]
        WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        // Home Increment Block
                        Button(action: { homeScore += 1; pushToPhone() }) {
                            VStack(spacing: 2) {
                                Text("HOME").font(.system(size: 10, weight: .bold)).foregroundColor(.blue)
                                Text("\(homeScore)").font(.title2).bold()
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue.opacity(0.15))
                        
                        // Away Increment Block
                        Button(action: { awayScore += 1; pushToPhone() }) {
                            VStack(spacing: 2) {
                                Text("AWAY").font(.system(size: 10, weight: .bold)).foregroundColor(.red)
                                Text("\(awayScore)").font(.title2).bold()
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red.opacity(0.15))
                    }
                    
                    HStack(spacing: 6) {
                        // Period Cycle Selector Toggle
                        Button(action: {
                            period = period < totalPeriods ? period + 1 : 1
                            pushToPhone()
                        }) {
                            Text("PER: \(period)/\(totalPeriods)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.yellow)
                        }
                        
                        // Timer Start / Pause Switch Flag
                        Button(action: { isRunning.toggle(); pushToPhone() }) {
                            Text(isRunning ? "PAUSE" : "START")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(isRunning ? .orange : .green)
                        }
                    }
                    
                    // Match Zero-Reset
                    Button("Reset Values") {
                        homeScore = 0
                        awayScore = 0
                        period = 1
                        isRunning = false
                        pushToPhone()
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 4)
            }
            // FIXED: APPLE WATCH VISUAL HUD BANNER OVERLAY CARD
            if showWatchAlert {
                    VStack {
                        Text(watchAlertText)
                            .font(.caption2).bold()
                            .multilineTextAlignment(.center)
                            .padding(8)
                            .background(Color.purple.cornerRadius(8))
                            .shadow(radius: 4)
                        Spacer()
                    }
                    .transition(.move(edge: .top))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.showWatchAlert = false }
                    }
                }
        }
        .onAppear {
            if WCSession.isSupported() {
                WCSession.default.delegate = sessionDelegate
                WCSession.default.activate()
            }
        }
    }
}
