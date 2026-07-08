# VoiceSlave

VoiceSlave is a local-first macOS menu bar dictation utility for fast Korean,
English, and code-mixed dictation.

The app has two build paths:

- `VoiceSlave.xcodeproj` for Xcode Release builds and archive/export.
- `./scripts/package-app.sh` for a local unsigned `.app` bundle from SwiftPM.

The product logic lives in `VoiceSlaveCore` so privacy, mode gating, insertion,
history, vocabulary, and latency behavior can be tested without a GUI session.
The `VoiceSlave` executable provides the AppKit/SwiftUI menu bar shell, Settings
window, recording overlay, and macOS runtime adapters.

## Try The App

```sh
./scripts/package-app.sh
open dist/VoiceSlave.app
```

For the full setup flow, screenshots, permissions, and troubleshooting, read
[docs/onboarding.md](docs/onboarding.md).

![Settings](docs/assets/screenshots/settings.png)

![Recording overlay](docs/assets/screenshots/overlay.png)

## Xcode Build

Install Xcode, open it once, then select it:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
./scripts/build-xcode.sh
```

For an archived app export:

```sh
./scripts/archive-xcode.sh
```

This repository also keeps the SwiftPM path working for agents and machines that
only have Command Line Tools installed.

## Verification

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/package-app.sh
./scripts/desktop-qa-smoke.sh
./scripts/measure-warm-latency.sh
```

The local STT boundary is represented by `TranscriptionEngine` and the
WhisperKit-oriented `WhisperKitTranscriptionEngine`, using the verified
WhisperKit large-v3 turbo class default model identifier
`large-v3-v20240930_turbo`. OpenAI post-processing defaults to `gpt-5.4-nano`
with `gpt-5.4-mini` as the quality upshift.
