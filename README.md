# VoiceSlave

VoiceSlave is a local-first macOS menubar dictation utility scaffolded for the
`mac-voice-dictation-app` PRD.

The current implementation keeps product logic in `VoiceSlaveCore` so privacy,
mode gating, insertion, history, vocabulary, and latency behavior can be tested
without a GUI session. The executable target provides a native AppKit/SwiftUI
menubar shell with Settings and recording overlay surfaces.

## Verification

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/measure-warm-latency.sh
./scripts/desktop-qa-smoke.sh
```

The local STT boundary is represented by `TranscriptionEngine` and the
WhisperKit-oriented `WhisperKitTranscriptionEngine`, using the verified
WhisperKit large-v3 turbo class default model identifier
`large-v3-v20240930_turbo`. OpenAI post-processing defaults to `gpt-5.4-nano`
with `gpt-5.4-mini` as the quality upshift.
