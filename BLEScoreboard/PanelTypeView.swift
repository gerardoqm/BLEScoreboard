import SwiftUI

/// Chooses the driver chip setting for the board's LED panel. A panel cannot tell the board what chip it has, so the right
/// setting is found by trying: pick one, the board restarts with it, and the panel should show clean colors.
struct PanelTypeView: View {
    @ObservedObject var ble: AdvancedBLEManager
    @State private var confirming: Int?
    
    var body: some View {
        List {
            Section {
                Text("If the panel stays dark, shows wrong colors or flickers, try another setting. Each choice is saved on the board, which restarts and reconnects. A setting is right when the scores and the clock look clean and the colors are correct.")
                    .font(.footnote).foregroundColor(.secondary)
                Text("With no signal on the panel, press BOOT on the board within 2 seconds after turning it on to step through the settings with its test pattern.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            Section {
                ForEach(Array(AdvancedBLEManager.panelPresetNames.enumerated()), id: \.offset) { index, name in
                    Button {
                        confirming = index
                    } label: {
                        HStack {
                            Text(index == 0 ? "\(name) (default)" : name).foregroundColor(.primary)
                            Spacer()
                            if ble.boardPanelPreset == index { Image(systemName: "checkmark").foregroundColor(.green) }
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
        }
        .navigationTitle(Text("Panel type"))
        .confirmationDialog(Text("Restart the board with this setting?"), isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible) {
            if let index = confirming {
                Button(AdvancedBLEManager.panelPresetNames[index]) { ble.setPanelPreset(index); confirming = nil }
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        }
    }
}
