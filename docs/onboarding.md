# VoiceSlave Onboarding Guide

VoiceSlave is a local-first macOS menu bar dictation app. The app is intentionally a background utility: after launch, look for `VS` in the macOS menu bar instead of the Dock.

## Install From Source

### Option A: Local unsigned app bundle

Use this when you want to try the app immediately on a development Mac.

```sh
./scripts/package-app.sh
open dist/VoiceSlave.app
```

If macOS blocks the unsigned app, right-click `dist/VoiceSlave.app`, choose Open, and confirm. For a local development checkout you can also remove quarantine:

```sh
xattr -dr com.apple.quarantine dist/VoiceSlave.app
open dist/VoiceSlave.app
```

### Option B: Xcode build

Install Xcode, open it once, then select it:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
./scripts/build-xcode.sh
```

For an archived `.app` export:

```sh
./scripts/archive-xcode.sh
open dist/xcode-export
```

Signing, notarization, and DMG packaging are intentionally separate release steps. Use a Developer ID certificate before sharing the app outside your own Mac.

## First Launch

1. Launch `VoiceSlave.app`.
2. Find `VS` in the menu bar.
3. Open `VS` -> `Settings`.
4. Confirm the default shortcut and mode.
5. Keep `Preload model for faster dictation` enabled for lower warm-path latency.

![Settings](assets/screenshots/settings.png)

## Permissions

VoiceSlave needs:

- Microphone permission to record local dictation audio.
- Accessibility permission for global shortcut handling and optional Typing Mode.

Open macOS System Settings:

- Privacy & Security -> Microphone -> enable VoiceSlave.
- Privacy & Security -> Accessibility -> enable VoiceSlave.

Normal dictation should stay blocked until microphone, accessibility, and model setup are ready.

## Dictation Flow

1. Choose `Dictation` mode for fully local cleanup and insertion.
2. Press the configured shortcut or choose `Start Dictation` from the `VS` menu.
3. Speak a Korean-English/code mixed phrase.
4. Press Stop in the overlay.
5. VoiceSlave inserts text at the current cursor through clipboard paste and then best-effort restores the previous clipboard.

![Recording overlay](assets/screenshots/overlay.png)

## Cloud Modes

`Cleanup` and `Prompt` are visible but disabled until an OpenAI API key is available. When enabled, cloud post-processing sends only:

- raw transcript text
- explicit Personal Vocabulary hints

VoiceSlave must not send audio, clipboard contents, selected text, cursor surroundings, active app context, or app names.

## History And Deletion

History stores local SQLite metadata and local audio-file references under Application Support. The app excludes the history directory from iCloud backup and supports individual delete, full delete, and optional retention cleanup.

## Troubleshooting

- No `VS` item: make sure the app is running with `open dist/VoiceSlave.app`.
- Permission still denied: quit and reopen VoiceSlave after toggling macOS permission switches.
- Paste-hostile app: enable Typing Mode in Settings.
- Sharing with another Mac: use Xcode archive/export with Developer ID signing and notarization first.
