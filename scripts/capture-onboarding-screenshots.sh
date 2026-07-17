#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-docs/assets/screenshots}"
mkdir -p "$OUT_DIR"

APP_PATH="$(./scripts/package-app.sh | tail -n 1)"

"$APP_PATH/Contents/MacOS/Sokki" --show-settings > /tmp/sokki-settings.log 2>&1 &
pid=$!
sleep 2.5
screencapture -x "$OUT_DIR/settings-full.png"
sips -c 620 760 --cropOffset 195 580 "$OUT_DIR/settings-full.png" --out "$OUT_DIR/settings.png" >/dev/null
rm -f "$OUT_DIR/settings-full.png"
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

"$APP_PATH/Contents/MacOS/Sokki" --show-overlay > /tmp/sokki-overlay.log 2>&1 &
pid=$!
sleep 2.5
screencapture -x "$OUT_DIR/overlay-full.png"
sips -c 200 720 --cropOffset 860 600 "$OUT_DIR/overlay-full.png" --out "$OUT_DIR/overlay.png" >/dev/null
rm -f "$OUT_DIR/overlay-full.png"
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true

echo "$OUT_DIR/settings.png"
echo "$OUT_DIR/overlay.png"
