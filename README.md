# BLEScoreboard Remote Control (iOS & watchOS App)

A native, low-latency iOS controller and watchOS extension built with **SwiftUI**, **CoreBluetooth**, and **WatchConnectivity**. This app serves as the master command center for the custom ESP32-S3 HUB75 LED Matrix Scoreboard, providing fluid score management, game clock sequencing, and device management right from your wrist or hand.

## ✨ Key Features

- **Radar Board Scanner Screen:** Scans and displays nearby active scoreboards. Seamlessly link to your designated display to prevent interference on multi-court venues.
- **Dynamic Language & Unit Naming:** Zero hardcoded words. Type custom identifiers directly into the app (e.g., Change "Period" to "Quarter", "Tiempo", or "Half"). Uses Apple's native `NumberFormatter` class to apply localized grammatical ordinal suffixes matching your phone's active language region (e.g., `1st`, `1er`, `1.º`).
- **Unified Master Clock Engine:** A centralized Swift background `Timer` manages the match clock countdown, eliminating data-stream collisions.
- **Accidental Disconnect Protection:** If the scoreboard drops power or loses connection mid-game, the timer continues ticking cleanly on your phone/watch. Upon reboot, the board automatically re-pairs and catches up to the exact live timeline parameters instantly.
- **Live Hardware Telemetry:** Displays a real-time, color-coded hardware battery percentage readout beamed straight from the scoreboard's resistor divider circuit.
- **Immersive Visual & Haptic HUD Overlays:** Triggers crisp double-taps for period kickoffs, distinct warning pulses for intermissions, and a triple-whistle sequence for the final match completion across both the iPhone screen and the Apple Watch haptic core.

## 🛠️ Xcode Deployment & Setup

### Requirements
- macOS running **Xcode 15+**
- A physical iPhone running **iOS 16+** and an paired Apple Watch running **watchOS 9+**

### Step-by-Step Configuration

1. **Clone the Repository:**
   ```bash
   git clone https://github.com
   ```
2. **Open the Workspace:** Open `BLEScoreboard.xcodeproj` in Xcode.
3. **Configure Code Signing (Crucial):**
   - Click the top-level project root (`BLEScoreboard`).
   - Open the **Signing & Capabilities** tab.
   - Check **"Automatically manage signing"**.
   - In the **Team** dropdown, select your personal Apple ID developer profile.
   - Under the *TARGETS* sidebar column on the left, click on **`ScoreboardWatch Watch App`** and select the exact same **Team Account Profile name** there as well.
4. **Deploy:** Plug your physical iPhone into your Mac via USB, select it in the target device dropdown menu, and click **Run (Play)**.

> 🔒 **Privacy Permissions Note:** The application's `Info.plist` is pre-configured with the mandatory `Privacy - Bluetooth Always Usage Description` string key required by Apple to prevent runtime permission crashes.
