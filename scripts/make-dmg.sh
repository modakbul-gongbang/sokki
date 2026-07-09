#!/usr/bin/env bash
# Builds dist/Sokki-<version>.dmg from dist/Sokki.app (run package-app.sh first).
set -euo pipefail

APP_DIR="${APP_DIR:-dist/Sokki.app}"
VERSION="${APP_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")}"
DMG_PATH="dist/Sokki-${VERSION}.dmg"
STAGING="$(mktemp -d)/Sokki"

test -d "$APP_DIR" || { echo "missing $APP_DIR — run scripts/package-app.sh first" >&2; exit 1; }

mkdir -p "$STAGING"
ditto "$APP_DIR" "$STAGING/Sokki.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "Sokki ${VERSION}" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG_PATH" >/dev/null
rm -rf "$(dirname "$STAGING")"

echo "$DMG_PATH"
