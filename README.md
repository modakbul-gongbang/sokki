# VoiceSlave

VoiceSlave is a local-first macOS menu bar dictation utility for fast Korean,
English, and code-mixed dictation. Press a global shortcut anywhere, speak,
press it again — your words are pasted at the cursor.

- **Fast, real dictation**: streaming Apple Speech recognition (on-device when
  available) with live partial transcripts in the recording pill. No model
  download, works offline.
- **Superwhisper-style UX**: tap the shortcut to toggle, or hold it to talk and
  release to insert (push-to-talk on the same binding). `esc` cancels.
- **Zero-permission hotkey**: the global shortcut uses Carbon hotkeys and works
  before granting anything; mic + speech permissions gate recording, and
  Accessibility only gates auto-paste (clipboard fallback otherwise).
- **Bottom-center recording pill**: live waveform, elapsed time, mode chip,
  live transcript, then `Inserted · 0.8s` feedback. The panel never steals
  focus from the target app.
- **Vocabulary & replacements**: case-insensitive deterministic fixes
  ("보이스 슬레이브" → "VoiceSlave") that are also fed to the recognizer as hints.
- **History with retention**: searchable local SQLite history (+ optional audio),
  30-day auto-cleanup by default, one-click delete all.
- **Optional AI modes**: Cleanup/Prompt post-processing via OpenAI with the key
  stored in the macOS Keychain; transcript-only payloads, local fallback on
  failure.

The product logic lives in `VoiceSlaveCore` so privacy, mode gating, insertion,
history, vocabulary, replacement, and latency behavior can be tested without a
GUI session. The `VoiceSlave` executable provides the AppKit/SwiftUI menu bar
shell, recording HUD, Settings window, onboarding, and macOS runtime adapters.

## Try The App

```sh
./scripts/package-app.sh
ditto dist/VoiceSlave.app /Applications/VoiceSlave.app
open /Applications/VoiceSlave.app
```

Installed in `/Applications`, the app launches from Spotlight like any other app.

A welcome window walks you through permissions on first launch. Then press
`⌃⌥Space` in any app and start talking. Settings live behind the mic icon in
the menu bar.

For the full setup flow, screenshots, permissions, and troubleshooting, read
[docs/onboarding.md](docs/onboarding.md).

![Settings](docs/assets/screenshots/settings.png)

![Recording pill](docs/assets/screenshots/overlay.png)

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

## Architecture Notes

- `Sources/VoiceSlaveCore` — engine-agnostic core: settings, permissions model,
  dictation pipeline (cleanup → replacements → optional cloud transform),
  SQLite history with retention, vocabulary store, insertion service, latency
  math.
- `Sources/VoiceSlave` — the app: `RecordingCoordinator` state machine
  (idle → recording → transcribing → notice), `SpeechSession` (AVAudioEngine +
  SFSpeechRecognizer streaming, level metering, audio capture), Carbon
  `HotKeyCenter`, non-activating HUD panel, Settings/Onboarding SwiftUI.
- STT is behind the `TranscriptionEngine` boundary; the WhisperKit identifiers
  (`large-v3-v20240930_turbo` class) remain the planned upgrade path for a
  bundled-model engine. OpenAI post-processing defaults to `gpt-5.4-nano`
  with `gpt-5.4-mini` as the quality upshift.
