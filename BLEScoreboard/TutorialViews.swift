import SwiftUI

/// Short "how to link your board" card shown under the scanning animation.
struct LinkHelpCard: View {
    var onOpenTutorial: () -> Void

    private let steps: [(icon: String, text: LocalizedStringKey)] = [
        ("power", "Power on your scoreboard. Its LED blinks blue while it waits for your phone."),
        ("iphone.radiowaves.left.and.right", "Keep your phone close and Bluetooth on. Your board appears in this list."),
        ("link", "Tap Link Display. The LED turns solid green when you are connected."),
        ("arrow.triangle.2.circlepath", "If the link drops, the clock keeps running on your phone and the board relinks by itself.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to link your scoreboard").font(.subheadline).bold()
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle().fill(Color.green.opacity(0.18)).frame(width: 28, height: 28)
                        Image(systemName: step.icon).font(.system(size: 13, weight: .semibold)).foregroundColor(.green)
                    }
                    Text(step.text).font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Step \(index + 1)"))
            }
            Button(action: onOpenTutorial) {
                Label("See the full tutorial", systemImage: "book")
                    .font(.footnote).bold()
            }
            .padding(.top, 2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}

/// Paged walkthrough of the app. Screenshots are bundled per language (see Assets.xcassets/Tutorial).
struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Page {
        let title: LocalizedStringKey
        let text: LocalizedStringKey
        let image: String?   // base name; "-en" / "-es" is appended
        let icon: String
    }

    private let pages: [Page] = [
        Page(title: "1. Find your scoreboard",
             text: "Power on the board and open the app. The radar searches for nearby scoreboards. The board's LED blinks blue while it waits.",
             image: "tutorial-1-scan", icon: "dot.radiowaves.left.and.right"),
        Page(title: "2. Link it",
             text: "Tap Link Display next to your board. At a venue with several courts, pick the name of your own board. The LED turns solid green.",
             image: "tutorial-2-link", icon: "link"),
        Page(title: "3. Run the game",
             text: "Use the steppers for the score and Start, Pause and Reset for the clock. The timer runs on your phone, so the game keeps going if the link drops.",
             image: "tutorial-3-game", icon: "timer"),
        Page(title: "4. Set up the match",
             text: "Choose the period, the number of periods and the panel brightness. Rename the period unit (Quarter, Half, Tiempo) and the board from the top card.",
             image: "tutorial-4-setup", icon: "slider.horizontal.3"),
        Page(title: "5. Choose panel colors",
             text: "Tap Panel Colors in the top card. Pick the color of the timer (running and stopped), the period, each team's name and score, and the two start alerts. Use the switch on a row to hide that element on the panel; an alert you switch off does not play. The preview shows the panel as you choose, and the board remembers your choices.",
             image: "tutorial-5-colors", icon: "paintpalette"),
        Page(title: "6. Start alerts",
             text: "When a game or a period starts, the panel flashes its border and scrolls a message across it in the color you chose. Use the play buttons on the colors page to try the alerts in the preview and on your board.",
             image: "tutorial-6-alerts", icon: "play.circle"),
        Page(title: "7. Apple Watch and alerts",
             text: "The Watch app lets you add or subtract points, change the period and start or pause the clock from your wrist. It follows your phone, so both always show the same score. You get a banner and a tap when a period starts and when the match ends.",
             image: "tutorial-7-watch", icon: "applewatch"),
        Page(title: "8. Try the simulated board",
             text: "No board at hand? Tap Try the simulated board on the Find Scoreboards screen. At the bottom of the match screen, a simulated panel shows what the real board shows: scores, clock, period, names, your colors and the start alerts. Control it from the phone or the Watch. With a real board linked it mirrors the board and shows whether the two are in sync.",
             image: "tutorial-8-simulator", icon: "display")
    ]

    /// "es" when the phone is set to Spanish, otherwise English.
    private var languageSuffix: String { AppLanguage.current.code }

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 16) {
                        if let image = item.image {
                            Image("\(image)-\(languageSuffix)")
                                .resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                                .shadow(radius: 4)
                                .frame(maxHeight: 430)
                                .padding(.horizontal, 40)
                        } else {
                            Image(systemName: item.icon).font(.system(size: 90)).foregroundColor(.green).frame(height: 300)
                        }
                        Text(item.title).font(.title3).bold()
                        Text(item.text).font(.subheadline).foregroundColor(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 28)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 8)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .navigationTitle("Tutorial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}
