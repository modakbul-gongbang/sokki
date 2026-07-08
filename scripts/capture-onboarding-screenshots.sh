#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-docs/assets/screenshots}"
mkdir -p "$OUT_DIR"

APP_PATH="$(./scripts/package-app.sh | tail -n 1)"

"$APP_PATH/Contents/MacOS/VoiceSlave" --show-settings > /tmp/voiceslave-settings.log 2>&1 &
pid=$!
sleep 2
screencapture -x "$OUT_DIR/settings-full.png"
sips -c 650 740 --cropOffset 115 590 "$OUT_DIR/settings-full.png" --out "$OUT_DIR/settings.png" >/dev/null
rm -f "$OUT_DIR/settings-full.png"
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

"$APP_PATH/Contents/MacOS/VoiceSlave" --show-settings --show-overlay > /tmp/voiceslave-overlay.log 2>&1 &
pid=$!
sleep 2
screencapture -x "$OUT_DIR/overlay-full.png"
sips -c 650 740 --cropOffset 115 590 "$OUT_DIR/overlay-full.png" --out "$OUT_DIR/overlay.png" >/dev/null
rm -f "$OUT_DIR/overlay-full.png"
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

echo "$OUT_DIR/settings.png"
echo "$OUT_DIR/overlay.png"
