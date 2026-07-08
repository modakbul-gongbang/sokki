#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="VoiceSlave"
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
    "$(EXECUTABLE_NAME)": "VoiceSlave",
    "$(PRODUCT_BUNDLE_IDENTIFIER)": "com.hoyeon.VoiceSlave",
    "$(PRODUCT_NAME)": "VoiceSlave",
}
for old, new in replacements.items():
    source = source.replace(old, new)
Path("dist/VoiceSlave.app/Contents/Info.plist").write_text(source)
PY

cat > "$APP_DIR/Contents/PkgInfo" <<'EOF'
APPL????
EOF

echo "$APP_DIR"
