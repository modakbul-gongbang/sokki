---
name: sokki-install
description: Install the Sokki macOS dictation app from a GitHub Release DMG or from source, walk the user through permissions, and verify dictation works.
---

# Sokki installation

Use this file for installing Sokki on a Mac and getting a first dictation
working. For day-to-day usage and troubleshooting, read
[docs/onboarding.md](docs/onboarding.md).

Sokki is a menu bar app: after launch there is no Dock icon — look for the
microphone icon in the macOS menu bar.

## Agent Install Contract

If you are an AI agent and the user asks you to install Sokki from this file,
do the work end to end without asking follow-up questions, except where a step
requires a user-owned action. The user-owned actions are:

1. Clicking **Allow** on the Microphone and Speech Recognition permission prompts.
2. Enabling **Sokki** under System Settings → Privacy & Security → **Accessibility** (needed for auto-paste and the optional fn key trigger; without it, results are still copied to the clipboard).
3. Optionally setting System Settings → Keyboard → *"Press 🌐 key to"* → **Do Nothing** if they enable the fn key trigger.

Tell the user exactly when to perform each of these, then continue.

Requirements: macOS 14+ on Apple Silicon. Installing from source additionally
needs Xcode Command Line Tools (`xcode-select --install`) — full Xcode is not
required.

## Install from a GitHub Release (preferred)

```bash
cd "$(mktemp -d)"
gh release download --repo yansfil/sokki --pattern "*.dmg" || {
  curl -fsSL -o Sokki.dmg "$(curl -fsSL https://api.github.com/repos/yansfil/sokki/releases/latest \
    | /usr/bin/python3 -c 'import json,sys; print([a["browser_download_url"] for a in json.load(sys.stdin)["assets"] if a["name"].endswith(".dmg")][0])')"
}
DMG="$(ls *.dmg | head -1)"
MOUNT="$(hdiutil attach "$DMG" -nobrowse | awk -F'\t' '/\/Volumes\//{print $NF}' | head -1)"
rm -rf /Applications/Sokki.app
ditto "$MOUNT/Sokki.app" /Applications/Sokki.app
hdiutil detach "$MOUNT" >/dev/null
xattr -dr com.apple.quarantine /Applications/Sokki.app
open /Applications/Sokki.app
```

The `xattr` line matters: release builds are ad-hoc signed (not notarized
yet), so without it Gatekeeper blocks the first launch. If the user prefers
not to strip quarantine, they can right-click `/Applications/Sokki.app` →
Open → Open once instead.

## Install from source

```bash
INSTALL_DIR="${SOKKI_DIR:-$HOME/projects/sokki}"
if [ -d "$INSTALL_DIR/.git" ]; then
  git -C "$INSTALL_DIR" pull --ff-only
else
  git clone https://github.com/yansfil/sokki "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"
./scripts/package-app.sh
rm -rf /Applications/Sokki.app
ditto dist/Sokki.app /Applications/Sokki.app
open /Applications/Sokki.app
```

Source builds run on the local machine, so there is no quarantine flag to
remove.

## First-run walkthrough

1. On first launch a **Welcome to Sokki** window opens.
2. Ask the user to click **Allow…** for Microphone and Speech Recognition
   (user-owned action 1). Both prompts are standard macOS dialogs.
3. Ask the user to pick their dictation language in step 2 of the welcome
   window — **한국어**, **English (US)**, or Automatic. Important: "Automatic"
   follows the macOS *system* language; a Korean speaker on an
   English-language Mac should pick 한국어 explicitly.
4. For auto-paste at the cursor, ask the user to enable Sokki under System
   Settings → Privacy & Security → Accessibility (user-owned action 2). Skipping
   this is fine — results are copied to the clipboard instead.
5. Have the user try it: click into the welcome window's test field, press
   `⌃⌥Space`, speak, press `⌃⌥Space` again. The recording pill appears
   top-center with a live waveform.

## Optional: Whisper engine (best quality)

For noticeably better Korean-English mixed transcription, enable the Whisper
model pack (~1.6 GB one-time download, stored locally, deletable):

1. Menu bar mic icon → Settings… → **Dictation** tab → Engine →
   select **Whisper large-v3 turbo**.
2. Click **Download (≈1.6 GB)** and let the progress bar finish. The model
   loads automatically afterwards; dictation falls back to Apple Speech until
   it is ready.

## Optional: fn key trigger

Settings → General → **"Also trigger with the 🌐 fn key"**. This needs the
same Accessibility permission as auto-paste (user-owned action 2) and works
best with user-owned action 3 (globe key → Do Nothing). A bare fn tap then
toggles dictation; holding fn works as push-to-talk.

## Verify

```bash
pgrep -fl "/Applications/Sokki.app" || echo "NOT RUNNING"
mdfind "kMDItemKind == 'Application' && kMDItemDisplayName == 'Sokki'" | grep -q /Applications/Sokki.app && echo "Spotlight OK"
codesign -dv /Applications/Sokki.app 2>&1 | grep Identifier
```

Then confirm with the user that a real dictation works: cursor into any text
field, `⌃⌥Space`, speak, `⌃⌥Space` — the text should appear at the cursor
(or land on the clipboard with a "Copied — press ⌘V" notice if Accessibility
was skipped).

## Troubleshooting

- **No menu bar icon** — the app is running but only lives in the menu bar; check `pgrep -fl Sokki.app`. If nothing, `open /Applications/Sokki.app`.
- **"Sokki is damaged / can't be opened"** — quarantine on an unsigned build: `xattr -dr com.apple.quarantine /Applications/Sokki.app`.
- **Shortcut does nothing** — another app may own `⌃⌥Space`; rebind in Settings → General.
- **Waveform flat while recording** — Microphone permission missing, or the wrong input device is selected in macOS Sound settings.
- **Permission shows Denied after reinstalling/rebuilding** — ad-hoc signatures change per build, which invalidates old TCC grants. Remove Sokki from the permission list in System Settings and grant it again (or `tccutil reset Accessibility com.hoyeon.Sokki` first).
- **First dictation came back empty** — should not happen (the app prewarms the recognizer and re-transcribes captured audio), but if it does, check `log show --predicate 'subsystem == "com.hoyeon.Sokki"' --info --last 5m`.
