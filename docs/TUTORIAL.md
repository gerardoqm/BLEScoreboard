# BLEScoreboard tutorial

How to link your scoreboard and run a game with the app. The same walkthrough is built into the app: tap the **?** button.

> Screenshots are generated from the app's debug demo mode (`-demo scanning|list|connected|simulate`, see `tools/take-screenshots.sh`), so they use sample data. [Versión en español](TUTORIAL.es.md)

## 1. Find your scoreboard

Power on the board and open the app. The radar searches for nearby scoreboards, and the board's LED **blinks blue** while it waits for your phone. Keep Bluetooth on and the phone close.

<img src="images/1-scan-en.png" width="280" alt="Searching for scoreboards with the help card">

If Bluetooth is off, the screen tells you so instead of showing the radar.

## 2. Link it

Boards appear in the list as they are found, and the app keeps looking for more. Tap **Link Display** next to your own board; at a venue with several courts, pick the board name you gave it. The LED turns **solid green** when you are connected.

<img src="images/2-link-en.png" width="280" alt="List of scoreboards found">

## 3. Run the game

The top card shows the link status, the board name, the board's battery (next to the unit name) and the **Board Firmware**, **Panel Colors** and brightness controls. Below it are the team names and one box with the period title, both scores, the countdown and the period controls. **Start**, **Pause** and the reset button control the countdown, and the minutes stepper sets the period length. The clock follows the real time on your phone, so the game keeps going if the link drops or iOS suspends the app. When the board is back, the app relinks and resends the live state.

Every time a score goes up, from the phone or the watch, a **Goal by <team>** animation plays on the phone and the panel, with the emoji you choose in Panel Colors.

<img src="images/3-game-en.png" width="280" alt="Scores, clock and match settings">

## 4. Set up the match

Use the arrows next to **Period** to go to the previous or next period (the clock stops and shows the full next period, ready to start), and the **Total** menu for the number of periods. The panel brightness sits next to **Panel Colors**. In the top card you can rename the period unit (for example Quarter, Half or Tiempo), type emoji in the team names, and give the board its own name with **Rename**: the board saves it, restarts and relinks. Board names use plain characters only (1 to 20).

<img src="images/4-setup-en.png" width="280" alt="Period controls and the simulated panel">

## 5. Choose panel colors

Tap **Panel Colors** in the top card. Pick the color of the timer (running and stopped), the period, each team's name and score, and the two start alerts, using the swatches or any color from the color picker. The preview at the top shows the panel as you choose. The board saves the colors, and the app sends them again every time you connect. Use the switch on a row to **hide** that element on the panel (the timer switch hides the timer whether it is running or stopped); an alert you switch off does not play. The preview and the simulated board hide it right away. **Reset colors** goes back to the default colors and leaves the switches as they are.

<img src="images/5-colors-en.png" width="280" alt="Panel Colors page with a live panel preview">

## 6. Start alerts

When a game starts (period 1) or a later period starts, the panel flashes its border and scrolls `GAME START` or `PERIOD 2` across the screen at triple size, in the alert's color, then returns to the scoreboard. The alert plays when the clock starts from the full period length; resuming after a pause does not repeat it. On the colors page, **Play game start alert** and **Play period start alert** try them in the preview and on your board.

<img src="images/6-alerts-en.png" width="280" alt="A start alert playing in the panel preview">

<img src="images/alert-game-start.gif" width="420" alt="Animation of the game start alert on the panel"> <img src="images/alert-period-start.gif" width="420" alt="Animation of the period start alert on the panel">

## 7. Apple Watch and alerts

The Watch app lets you add or subtract points (− and + for each team), change the period and start or pause the clock from your wrist. It follows your phone, so both always show the same score. A banner and a tap on your phone and watch announce when a period starts and when the match ends.

<img src="images/7-watch-en.png" width="200" alt="Apple Watch remote">

## 8. Try the simulated board

No board at hand, or want to see a whole match? On the Find Scoreboards screen tap **Try the simulated board**. The match screen works the same way. At the bottom, a simulated panel shows what the real board shows: scores, clock, period, team names (scrolling when they don't fit), your colors and the start alerts. Under it are score, period and start/pause buttons, and the Apple Watch controls it too.

When a real board is linked, the simulated panel is the live preview of that board: the board mirrors the app, and a status line shows **Board in sync** when the board's own clock matches. **Exit simulator** (top card) goes back to the board list.

<img src="images/8-simulator-button-en.png" width="240" alt="The Try the simulated board button"> <img src="images/8-simulator-en.png" width="240" alt="The simulated board at the bottom of the match screen">

## 9. Update the board firmware

Open **Board Firmware** in the top card. It shows the firmware on the board and the one inside the app, and updates the board over Bluetooth with a progress bar on the panel. The LED blinks red during the update, turns green when the new image is verified, and the board restarts by itself.

<img src="images/9-firmware-en.png" width="280" alt="The Board Firmware page with an update available">

## 10. Landscape scoreboard

Turn the phone sideways on the match screen and the simulated panel fills the screen, with the score, period and clock controls in one row below. The screen stays on, so the phone works as the scoreboard if the real panel does not.

<img src="images/10-landscape-en.png" width="560" alt="The landscape scoreboard">

## 11. Language

The globe button (top left of the Find Scoreboards screen, and in the top card of the match screen) forces English or Spanish, or follows the phone. The change applies at once to the whole app, the panel alerts and the Apple Watch.

## Troubleshooting

| Problem | What to try |
| :--- | :--- |
| The board does not appear | Check that it is powered and its LED blinks blue, that Bluetooth is on, and pull down on the list to rescan. |
| "Board firmware is outdated" | Flash the latest firmware from the `scoreboard_BT_ESP32S3` repository (USB, or Wi-Fi by IP address). |
| The LED blinks cyan | The link dropped. The board waits 30 seconds for the same phone, then resets and goes back to blue. |
| Colors, alerts or hidden elements do nothing on the panel | The board needs the latest firmware (protocol version 4). The colors page shows a warning when it is older. |
| Rename does nothing | The board needs current firmware; the status line under the field shows why. |
