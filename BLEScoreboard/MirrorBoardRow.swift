import SwiftUI

/// Links a second board that shows the same scoreboard. The phone talks to the first board only; the board relays to the second one.
struct MirrorBoardRow: View {
    @ObservedObject var ble: AdvancedBLEManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "rectangle.on.rectangle").foregroundColor(.teal)
                Text("Second display").font(.subheadline).bold()
                Spacer()
                if ble.mirrorLinked {
                    HStack(spacing: 4) {
                        Circle().fill(ble.mirrorOnline ? Color.green : Color.orange).frame(width: 8, height: 8)
                        Text(LocalizedStringKey(ble.mirrorOnline ? "Mirroring" : "Not answering")).font(.caption2).bold()
                            .foregroundColor(ble.mirrorOnline ? .green : .orange)
                        if let battery = ble.mirrorBattery {
                            Text("\(battery)%").font(.caption2).bold().monospacedDigit()
                                .foregroundColor(battery < 15 ? .red : (battery < 50 ? .orange : .green))
                        }
                    }
                }
            }
            if ble.boardIsMirror {
                Text("This board follows another board. Connect to the first board to control both.").font(.caption2).foregroundColor(.secondary)
                Button("Unlink") { ble.mirrorCommand(3) }.buttonStyle(.bordered).controlSize(.small).tint(.red)
            } else if ble.mirrorLinked {
                Button("Unlink") { ble.mirrorCommand(3) }.buttonStyle(.bordered).controlSize(.small).tint(.red)
            } else if ble.mirrorPairing {
                Text("Hold BOOT on the second board for 2 seconds until the panel says LINKED.").font(.caption2).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { ble.mirrorCommand(2) }.buttonStyle(.bordered).controlSize(.small)
                }
            } else {
                Button("Link a second display") { ble.mirrorCommand(1) }.buttonStyle(.bordered).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
