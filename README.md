# BLEScoreboard Remote Control (iOS & watchOS App)

A native, low-latency iOS controller and watchOS extension built with **SwiftUI**, **CoreBluetooth**, and **WatchConnectivity**. This app serves as the master command center for the custom ESP32-S3 HUB75 LED Matrix Scoreboard, providing fluid score management, game clock sequencing, and device management right from your wrist or hand.

## ✨ Key Features

- **Find Scoreboards Screen:** Scans with an animated radar and lists nearby active scoreboards. Seamlessly link to your designated display to prevent interference on multi-court venues.
- **English & Spanish:** The interface, alerts and Bluetooth permission prompt are localized through string catalogs (`Localizable.xcstrings`, `InfoPlist.xcstrings`). You can rename the period unit (e.g., "Quarter", "Tiempo", "Half") and ordinals follow the phone's region via `NumberFormatter`. The LED panel font is ASCII-only, so accents are stripped on the panel (`Águilas` shows as `AGUILAS`) and the bottom line is compact (`Q2 07:45`). To add a language, add it to the string catalogs and the project's Localizations.
- **Board Renaming:** Give each scoreboard its own name from the connected screen (1-20 plain characters). The board saves it and restarts, and the app reconnects on its own.
- **Unified Master Clock Engine:** A centralized Swift background `Timer` manages the match clock countdown, eliminating data-stream collisions.
- **Accidental Disconnect Protection:** If the scoreboard drops power or loses connection mid-game, the timer continues ticking cleanly on your phone/watch. When the board is back, the app reconnects and resends the live state.
- **Live Hardware Telemetry:** Displays a color-coded battery percentage read from the scoreboard's resistor divider, and warns when the board's firmware is older than the app expects.
- **Immersive Visual & Haptic HUD Overlays:** Triggers crisp double-taps for period kickoffs, distinct warning pulses for intermissions, and a triple-whistle sequence for the final match completion across both the iPhone screen and the Apple Watch haptic core.

## 📖 Tutorial

New to the app? Read the [tutorial](docs/TUTORIAL.md) ([en español](docs/TUTORIAL.es.md)) or tap the **?** button inside the app.

## 🛠️ Xcode Deployment & Setup

### Requirements
- macOS running **Xcode 15+**
- A physical iPhone running **iOS 16+** and an paired Apple Watch running **watchOS 9+**

### Step-by-Step Configuration

1. **Clone the Repository:**
   ```bash
   git clone https://github.com/gerardoqm/BLEScoreboard.git
   ```
2. **Open the Workspace:** Open `BLEScoreboard.xcodeproj` in Xcode.
3. **Configure Code Signing (Crucial):**
   - Click the top-level project root (`BLEScoreboard`).
   - Open the **Signing & Capabilities** tab.
   - Check **"Automatically manage signing"**.
   - In the **Team** dropdown, select your personal Apple ID developer profile.
   - Under the *TARGETS* sidebar column on the left, click on **`ScoreboardWatch Watch App`** and select the exact same **Team Account Profile name** there as well.
4. **Deploy:** Plug your physical iPhone into your Mac via USB, select it in the target device dropdown menu, and click **Run (Play)**.

> 🔒 **Privacy Permissions Note:** The Bluetooth usage description is set in the iOS target's build settings (`INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription`) and translated in `InfoPlist.xcstrings`. Without it iOS ends the app on first Bluetooth use.

> 📡 The byte-level Bluetooth protocol is documented in the firmware repository README (`scoreboard_BT_ESP32S3`). Update both together.



 🧠 SYSTEM DATA PIPELINE & OVER-THE-AIR ARCHITECTURE
 ───────────────────────────────────────────────────

 ┌─────────────────┐           (WatchConnectivity)          ┌────────────────┐
 │   APPLE WATCH   │ ◄────────────────────────────────────► │   IPHONE APP   │
 │ REMOTE EXTENSION│        Scores, Periods & Controls      │  (Master Clock │
 └─────────────────┘                                        │  & UI Engine)  │
                                                            └───────┬────────┘
                                                                    │
                                                                    │ (Bluetooth LE)
                                                                    │ Transmits 8-Byte Packet
                                                                    │ Receives 7-Byte Notify
                                                                    ▼
                                                            ┌────────────────┐
                                                            │    ESP32-S3    │
                                                            │ DISPLAY SERVER │
                                                            └───────┬────────┘
                                                                    │
                                                                    │ (HUB75 Flat Ribbon)
                                                                    ▼
                                                            ┌────────────────┐
                                                            │ 80x40 P4 PANEL │
                                                            │ (Graphics Out) │
                                                            └────────────────┘

 📶 BLUETOOTH RADIO SYSTEM CHECK (Onboard WS2812B RGB NeoPixel)
 ──────────────────────────────────────────────────────────────
 
  [ SEARCHING_NEW ]  ──► (Blinks Blue 🔵) ──► Looking for phone app handshake.
         ▲
         │ (If 30-Second Limit Drops)
         │
  [ RETRYING_PAST ]  ──► (Blinks Cyan 🌐) ──► Signal dropout! Keep clock ticking 
         ▲                                    on phone while scanning to recover link.
         │ (If Accidental Drop Occurs)
         │
 [LINKED_CONNECTED] ──► (Solid Green 🟢) ──► BLE Sync Handshake Active.
