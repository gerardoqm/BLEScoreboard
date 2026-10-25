# App changelog

Versions follow `major.minor.patch` (see the Versions section of the README). The number in brackets is the build.

## 1.6.0 (34)
- README and tutorial (English and Spanish) cover the goal word, the bigger emoji, the hundredths and their color, the second display, the panel type and the new unit name default; screenshots regenerated. The hundredths hint says firmware 1.6.1.

## 1.6.0 (33)
- The factory name of a match unit is "Period" in English and "Tiempo" in Spanish (it was "Periodo"). It is still the Unit Name field: type another name ("Quarter", "Cuarto"...) and it stays yours. The watch follows too.

## 1.6.0 (32)
- Bundled firmware 1.6.1 (the full-size hundredths and their color; the earlier 1.6.0 board build only had small hundredths in the clock color). Boards on 1.6.0 will be offered the update.

## 1.6.0 (31)
- The hundredths of a second are as big as the clock digits (00:41.36; the leading zeros give way when the period text is wide: 0:41.36, 41.36) and have their own color: the new "Hundredths" row on the Panel Colors page (red by default).

## 1.6.0 (30)
- Goal word: the goal alert's word is yours. On the Alerts and Sound page, type "Touchdown", "Home run", "Gol"... and the banner, the voice, the watch and the panel say "Touchdown by LION" ("Touchdown de LION" in Spanish). Empty = "Goal" / "Gol".
- A bigger emoji on the panel: the goal alert's picture is now 32 x 32 pixels (it was 16 x 16), centered on the panel's height, so it can be seen from the stands. Boards with older firmware keep the small one.
- Hundredths of a second in the last minute: while the clock runs in the last minute of a period, the panel shows it as "00:41.36", counting the hundredths down for the drama. Switch it off on the Alerts and Sound page. The preview in the app shows it too. Needs the bundled firmware 1.6.0 (protocol 12).

## 1.5.0 (29)
- Bundled firmware 1.5.1: in the panel diagnose mode a BOOT press now goes straight to the next test pattern (before, the board started normally and BOOT had to be pressed again within 2 seconds).

## 1.5.0 (28)
- Panel type page: a panel cannot tell the board which driver chip it has, so the page lets you try the 12 driver settings (6 chips, each with the clock phase as is or inverted). Pick one and the board saves it, restarts and the app reconnects. Bundled firmware 1.5.0 (protocol 11) also has a diagnose mode: press BOOT within 2 seconds of power-up, and BOOT steps through the settings with a test pattern on the panel (hold it for 3 seconds to leave).

## 1.5.0 (27)
- Bundled firmware 1.4.1: the board no longer joins Wi-Fi (no Wi-Fi password in the image); update it over Bluetooth with the Board Firmware page. A battery reading that fails no longer shows 0% for the second display.

## 1.5.0 (26)
- Second display: link a second board and it shows everything the first one does (score, clock, colors, alerts, goal and name pictures, end of match), so you can put one board on each side of the field. The phone keeps a single Bluetooth link; the first board relays to the second over ESP-NOW. Link them from "Second display" on the main page: tap "Link a second display", then hold BOOT for 2 seconds on the second board until both panels say LINKED. The row shows whether the second board answers and its battery. Needs firmware 1.4.0 on both boards. A linked board no longer joins the home Wi-Fi (update it over Bluetooth).

## 1.4.0 (25)
- The bundled firmware is built with PSRAM disabled. The firmware never uses PSRAM, and with it enabled a board with a faulty PSRAM restarts in a loop at power-up, so updating it over Bluetooth would not leave it working. The same image now suits every board.

## 1.4.0 (24)
- Live Activity: a second start now works. The app forgets an activity that was swiped away or ended by the system, picks up one left by an earlier run, and retries if iOS refused the start.
- A more natural voice: the announcements use the best voice installed for the language (premium, then enhanced, then standard), a little slower, and the Alerts and Sound page lets you pick another one and hear it. Downloading an Enhanced or Premium voice in Settings > Accessibility > Spoken Content > Voices makes a big difference.

## 1.4.0 (23)
- The end of a period (that is not the last one) now has a panel alert too: "END 1ST QUARTER" / "FIN 1ER TIEMPO". Its Panel switch on the Alerts and Sound page works like the others.
- The time left can be announced at any minute from 1 to 15 (5, 3 and 1 by default): the voice, the banner and the panel say it for whatever you pick ("7 minutes left", "quedan 12 minutos").

## 1.4.0 (22)
- Live Activity: once the clock starts, the match shows on the lock screen and in the Dynamic Island (scores, period, countdown), and iOS mirrors it on the Apple Watch. The countdown runs by itself; the scores update when they change. It ends when you disconnect, or 15 minutes after the final whistle. It has its own switch on the Alerts and Sound page. It is a new widget extension (ScoreboardLiveActivity).

## 1.4.0 (21)
- Alerts and Sound page (top card): for every event (goal, time left, match start, period start, period end, half time, match end) choose audio, the app banner and the panel separately, with a play button to try each one.
- Audio: goals and the time left are spoken in the app's language ("Goal by Whites", "5 minutes left" / "Gol de Blancos", "quedan 5 minutos"); referee whistles mark periods and a horn marks the start and end of the match. The time left is announced at 10, 5, 3, 2 and/or 1 minutes (5, 3 and 1 by default). Everything plays through the phone's current speaker, so a Bluetooth speaker works once it is paired and picked with the speaker button, music in other apps is lowered meanwhile, and the app keeps announcing while it is in the background.
- The panel shows the time left too ("5 MIN LEFT" / "QUEDAN 5 MIN") and the watch taps on it.

## 1.3.0 (20)
- The end of the match is announced on the panel ("FULL TIME" / "FIN DEL PARTIDO"): the app sends the alert, and with firmware 1.3.0 the board also announces it by itself when its clock reaches zero in the last period, so it works even if the phone is gone. The app sends the board the text in its language.
- The bundled firmware is 1.3.0.

## 1.3.0 (19)
- The match title uses the same ordinals and the unit name: "Match: 3rd of 4 quarters", "Partido: 1er de 4 tiempos" (the unit name is plural unless there is a single period).

## 1.3.0 (18)
- Period announcements use ordinals: "1st quarter", "2nd quarter", "3rd quarter" and "half time" in English, "1er tiempo", "2do periodo", "3er cuarto" and "medio tiempo" in Spanish, with the unit name you set. The first period now reads "1st quarter" instead of "GAME START" on the panel. The phone banner and the match title use the same ordinals.
- The scanning radar is drawn from the clock instead of a stored animation, so it can no longer end up off-center or out of step after the screen is rebuilt (for example after switching language).

## 1.3.0 (17)
- The countdown and the Start button no longer wrap on narrower phones (iPhone 17 Pro and smaller).
- New tutorial screenshots in English and Spanish (match screen, landscape, firmware page, watch with the countdown), made with `tools/take-screenshots.sh`; the tutorials describe the current screens and add the firmware, landscape and language sections.

## 1.3.0 (16)
- A goal alert on the panel is no longer cut at 16 characters: boards with firmware 1.2.3 take up to 32. Older boards still get the shortened text.
- The period start alert on the panel uses your unit name ("Cuarto 2", "Quarter 2") instead of always saying "Period".
- The bundled firmware is 1.2.3.

## 1.3.0 (15)
- Language switch: the globe button (on the scanner screen and in the match configuration card) forces English or Spanish, or follows the phone ("Automatic"). The choice is saved, applies at once to every text in the app, the board's alerts and the tutorial, and is sent to the Apple Watch, which switches too. Names left at the default ("HOME", "AWAY", "Period") change language with it.

## 1.2.0 (14)
- Landscape scoreboard: turn the phone sideways on the match screen (linked board or simulator) and the simulated LED panel fills the screen, with score, period and clock controls in one row below. The screen stays on, so the phone can serve as the scoreboard when the real panel does not work.

## 1.1.0 (13)
Version raised from 1.0.0 to 1.1.0: builds 2 to 12 added features (watch countdown, goal and half-time alerts, goal icon, emoji in names, compact layout), which is a minor version. From now on the version changes with each release and the build number with each build.

## 1.1.0 (12)
- The goal alert on the panel shows the scoring team's emoji inside the text ("GOAL BY 🦁 LIONS"). Needs firmware 1.2.2 (bundled in the app); older boards scroll the name without the emoji.
- The bundled firmware is 1.2.2.

## 1.1.0 (11)
- The battery indicator sits on the Unit Name line, at the right.

## 1.1.0 (10)
- A failed firmware update now says how far it got ("[sent / total, confirmed]") and logs its steps.
- The bundled firmware is 1.2.1 (Wi-Fi is switched off on the board during a Bluetooth update).

## 1.1.0 (9)
- Emoji in team names: type them in the name fields. On the panel (and in the preview) each emoji (up to two per team) is drawn as a 10 x 10 picture in line with the letters, and a name that is too wide scrolls as before. Needs firmware 1.2.0 (bundled in the app); older boards show the name without the emoji. The phone and watch show the emoji as typed.
- The bundled firmware is 1.2.0.

## 1.1.0 (8)
- Goal icon: pick the emoji that goes with the goal alert (Panel Colors page), or none. The phone and watch show it; for the board the app turns the emoji into a 16 x 16 picture and sends it, and the panel scrolls it in front of the text. Needs firmware 1.1.0 (bundled in the app).
- The bundled firmware is 1.1.0.

## 1.1.0 (7)
- Goal animation: every time a score goes up, from the phone or the watch, the phone shows a short animation reading "Goal by <team>" ("Gol de <equipo>" in Spanish), the panel scrolls it (up to 16 characters), the watch vibrates and shows the banner. It uses the Game start alert's color and its on/off switch.

## 1.1.0 (6)
- Half-time alert at the middle of the whole match: at the end of the middle period when the number of periods is even, halfway through the middle period when it is odd. It shows a banner and vibrates on the phone, vibrates the watch, scrolls HALF TIME on the board, and sends a notification if the app is not on screen.

## 1.1.0 (5)
- The clock follows the real time, so it stays right when iOS suspends the app, and it catches up when the app comes back.
- A notification announces the end of the match on the phone and the watch even when the app is not on screen.
- Changing the period stops the clock and shows the full next period, ready to start.
- Previous and next period buttons on the phone and the watch replace the period picker; the total stays a picker.
- The watch keeps the last state the phone stored and corrects for the time a message took to arrive, so it no longer shows a stale clock after sleeping. Reset on the watch also resets the clock.

## 1.1.0 (4)
- Apple Watch: the countdown and period moved to the top-left corner above the scores, the team names follow the names set on the iPhone, and the period button is now an icon.

## 1.1.0 (3)
- The Apple Watch app shows its version at the bottom of the screen. The watch and the iPhone app share one version number and build number.
- The Apple Watch shows the countdown (green while running, orange while stopped) and keeps counting between updates from the phone.
- Compact phone layout: period title, scores, countdown and period selectors share one box; brightness sits next to Panel Colors; the board preview has no duplicate controls.
- The bundled firmware is 1.0.2 (the Bluetooth update no longer stalls on a lost progress message).

## 1.0.0 (1)
First numbered version.
- Score, period and clock control from the iPhone and the Apple Watch; the app is the master clock.
- Panel colors, hide or show for each element, and start alerts (game and period).
- Simulated board: a live preview of the panel, usable without a board.
- Board renaming, battery and sync status, English and Spanish, in-app tutorial.
- Board Firmware page: shows the firmware version on the board and in the app, and updates the board over Bluetooth.
- The app version is shown on the Find Scoreboards screen and the Board Firmware page.
