#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="Sokki"
DIST_DIR="${DIST_DIR:-dist}"
APP_DIR="$DIST_DIR/$APP_NAME.app"
EXECUTABLE=".build/$CONFIGURATION/$APP_NAME"

swift build -c "$CONFIGURATION" --product "$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

python3 - <<'PY'
from pathlib import Path

source = Path("AppResources/Info.plist").read_text()
replacements = {
    "$(DEVELOPMENT_LANGUAGE)": "en",
    "$(EXECUTABLE_NAME)": "Sokki",
    "$(PRODUCT_BUNDLE_IDENTIFIER)": "com.hoyeon.Sokki",
    "$(PRODUCT_NAME)": "Sokki",
}
for old, new in replacements.items():
    source = source.replace(old, new)
Path("dist/Sokki.app/Contents/Info.plist").write_text(source)
PY

cat > "$APP_DIR/Contents/PkgInfo" <<'EOF'
APPL????
EOF

if [ -n "${APP_VERSION:-}" ]; then
  plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$APP_DIR/Contents/Info.plist"
fi

cp AppResources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

# Pin the ad-hoc signature's designated requirement to the bundle identifier
# instead of the default per-build cdhash, so macOS TCC grants (Microphone,
# Accessibility, Speech Recognition) survive rebuilds and upgrades.
codesign --force --sign - \
  --entitlements AppResources/Sokki.entitlements \
  --identifier com.hoyeon.Sokki \
  --requirements '=designated => identifier "com.hoyeon.Sokki"' \
  "$APP_DIR"
codesign --verify --strict "$APP_DIR"
if ! codesign -dr - "$APP_DIR" 2>&1 | grep -q 'designated => identifier "com.hoyeon.Sokki"'; then
  echo "Sokki code-signing identity is not stable." >&2
  exit 1
fi

echo "$APP_DIR"
