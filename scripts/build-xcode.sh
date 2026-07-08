#!/usr/bin/env bash
set -euo pipefail

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "xcodebuild is unavailable. Install Xcode, open it once, then run:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

xcodebuild \
  -project VoiceSlave.xcodeproj \
  -scheme VoiceSlave \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath .build/xcode-derived \
  build
