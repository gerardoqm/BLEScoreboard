#!/bin/bash
# Builds the board firmware and puts the image into the app, so the app can update boards over Bluetooth.
#
# Usage: tools/bundle-firmware.sh [path to the scoreboard_BT_ESP32S3 folder]
#
# The image contains the Wi-Fi and update passwords from secrets.h, so BLEScoreboard/Firmware/ is git-ignored:
# never commit these files. Run this before building the app whenever the firmware changes.
set -euo pipefail

FIRMWARE_DIR="${1:-$HOME/Documents/Arduino/scoreboard_BT_ESP32S3}"
APP_FIRMWARE_DIR="$(cd "$(dirname "$0")/.." && pwd)/BLEScoreboard/Firmware"
SKETCH="$FIRMWARE_DIR/scoreboard_BT_ESP32S3.ino"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

[ -f "$FIRMWARE_DIR/secrets.h" ] || { echo "Missing $FIRMWARE_DIR/secrets.h (copy secrets.h.example)"; exit 1; }

arduino-cli compile \
  --fqbn "esp32:esp32:esp32s3:FlashSize=16M,PartitionScheme=app3M_fat9M_16MB,PSRAM=opi,CDCOnBoot=cdc,UploadMode=default" \
  --build-path "$BUILD_DIR" "$FIRMWARE_DIR"

PROTOCOL=$(sed -n 's/^#define PROTOCOL_VERSION *\([0-9][0-9]*\).*/\1/p' "$SKETCH")
BUILD=$(sed -n 's/^#define FW_BUILD *\([0-9][0-9]*\).*/\1/p' "$SKETCH")
[ -n "$PROTOCOL" ] && [ -n "$BUILD" ] || { echo "Could not read PROTOCOL_VERSION and FW_BUILD from the sketch"; exit 1; }

mkdir -p "$APP_FIRMWARE_DIR"
cp "$BUILD_DIR/scoreboard_BT_ESP32S3.ino.bin" "$APP_FIRMWARE_DIR/scoreboard.bin"
printf '{"protocol": %s, "build": %s}\n' "$PROTOCOL" "$BUILD" > "$APP_FIRMWARE_DIR/firmware.json"
echo "Bundled firmware: protocol $PROTOCOL, build $BUILD ($(wc -c < "$APP_FIRMWARE_DIR/scoreboard.bin") bytes)"
