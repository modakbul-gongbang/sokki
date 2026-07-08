#!/usr/bin/env bash
set -euo pipefail

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "xcodebuild is unavailable. Install Xcode, open it once, then run:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

ARCHIVE_PATH="${ARCHIVE_PATH:-dist/VoiceSlave.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-dist/xcode-export}"

mkdir -p dist
xcodebuild \
  -project VoiceSlave.xcodeproj \
  -scheme VoiceSlave \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist AppResources/ExportOptions.plist

echo "$EXPORT_PATH"
