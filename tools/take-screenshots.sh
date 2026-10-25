#!/bin/bash
# Regenerates the tutorial screenshots in docs/images (English and Spanish) from the app's debug demo mode.
#
# Usage: tools/take-screenshots.sh
#
# Needs an iOS and a watchOS simulator runtime (Xcode > Settings > Components). It creates two throw-away simulators
# (an iPhone 17 Pro and an Apple Watch Series 11 46mm), builds the app for them, launches it with the `-demo` arguments
# (see applyDemoModeIfRequested in AdvancedBLEManager.swift) and `-AppleLanguages`, and removes the simulators at the end.
# The animated alert GIFs (alert-game-start.gif, alert-period-start.gif) are not regenerated.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGES="$ROOT/docs/images"
WORK="$(mktemp -d)"
IOS_RUNTIME="$(xcrun simctl list runtimes | awk '/iOS/ && !/unavailable/ {r=$NF} END {print r}')"
WATCH_RUNTIME="$(xcrun simctl list runtimes | awk '/watchOS/ && !/unavailable/ {r=$NF} END {print r}')"
[ -n "$IOS_RUNTIME" ] && [ -n "$WATCH_RUNTIME" ] || { echo "Install an iOS and a watchOS simulator runtime first."; exit 1; }

PHONE=$(xcrun simctl create "Shots iPhone" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "$IOS_RUNTIME")
WATCH=$(xcrun simctl create "Shots Watch" com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm "$WATCH_RUNTIME")
cleanup() { xcrun simctl delete "$PHONE" "$WATCH" 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT

cd "$ROOT"
xcodebuild -project BLEScoreboard.xcodeproj -scheme BLEScoreboard -configuration Debug -destination "id=$PHONE" -derivedDataPath "$WORK/phone" build -quiet
xcodebuild -project BLEScoreboard.xcodeproj -scheme "ScoreboardWatch Watch App" -configuration Debug -destination "id=$WATCH" -derivedDataPath "$WORK/watch" build -quiet
APP="$WORK/phone/Build/Products/Debug-iphonesimulator/BLEScoreboard.app"
WAPP="$WORK/watch/Build/Products/Debug-watchsimulator/ScoreboardWatch Watch App.app"

xcrun simctl boot "$PHONE"; xcrun simctl bootstatus "$PHONE" -b >/dev/null
xcrun simctl boot "$WATCH"; xcrun simctl bootstatus "$WATCH" -b >/dev/null
xcrun simctl install "$PHONE" "$APP"; xcrun simctl install "$WATCH" "$WAPP"
xcrun simctl status_bar "$PHONE" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularMode active --cellularBars 4 --wifiBars 3

shot() {   # device, bundle id, language, name, width, launch arguments...
  local dev=$1 bid=$2 lang=$3 name=$4 width=$5; shift 5
  local loc    # macOS ships bash 3.2, which cannot declare and fill an array in one `local`
  loc=(-AppleLanguages "($lang)" -AppleLocale "$([ "$lang" = es ] && echo es_MX || echo en_US)")
  xcrun simctl launch --terminate-running-process "$dev" "$bid" "${loc[@]}" "$@" >/dev/null
  sleep 8
  # simctl cannot write into ~/Documents, so the picture is made in the temp folder and copied
  xcrun simctl io "$dev" screenshot "$WORK/shot.png" >/dev/null 2>&1
  sips --resampleWidth "$width" "$WORK/shot.png" >/dev/null
  cp "$WORK/shot.png" "$IMAGES/$name-$lang.png"
  echo "$name-$lang"
}

for lang in en es; do
  B=com.gerardoqm.BLEScoreboard
  shot "$PHONE" $B $lang 1-scan 640 -demo scanning -staticRadar
  shot "$PHONE" $B $lang 2-link 640 -demo list
  shot "$PHONE" $B $lang 3-game 640 -demo connected
  shot "$PHONE" $B $lang 4-setup 640 -demo connected -scrollPreview
  shot "$PHONE" $B $lang 5-colors 640 -demo connected -showColors
  shot "$PHONE" $B $lang 6-alerts 640 -demo connected -showColors -playAlert game -alertFreeze 1.1
  shot "$PHONE" $B $lang 8-simulator-button 640 -demo list
  shot "$PHONE" $B $lang 8-simulator 640 -demo simulate -scrollPreview
  shot "$PHONE" $B $lang 9-firmware 640 -demo connected -showFirmware -fwDemo available
  shot "$PHONE" $B $lang 10-landscape 1000 -demo simulate -landscape
  shot "$PHONE" $B $lang 11-alerts 640 -demo connected -showAlerts
  shot "$PHONE" $B $lang 12-panel-type 640 -demo connected -showPanelType
  # the first launch of the watch app is slow, so it gets one throw-away launch
  xcrun simctl launch --terminate-running-process "$WATCH" com.gerardoqm.BLEScoreboard.watchkitapp -demo >/dev/null; sleep 12
  shot "$WATCH" com.gerardoqm.BLEScoreboard.watchkitapp $lang 7-watch 416 -demo
done
echo "Screenshots written to docs/images"
