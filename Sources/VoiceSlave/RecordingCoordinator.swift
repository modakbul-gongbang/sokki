import AppKit
import ApplicationServices
import Foundation
import VoiceSlaveCore

/// Drives the whole dictation lifecycle:
/// hotkey → record (live partials + levels) → transcribe → post-process →
/// insert into the frontmost app → history → notice → idle.
@MainActor
final class RecordingCoordinator: ObservableObject {
    enum NoticeKind: Equatable {
        case success
        case info
        case error
    }

    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case notice(NoticeKind, String)
    }

    static let maxRecordingSeconds: TimeInterval = 300
    private static let pushToTalkThreshold: TimeInterval = 0.5

    @Published private(set) var phase: Phase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    @Published private(set) var partialText = ""
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: 36)
    @Published private(set) var elapsed: TimeInterval = 0

    var onPhaseChange: ((Phase) -> Void)?
    var requestOnboarding: (() -> Void)?

    let model: AppModel
    private let hotKeys: HotKeyCenter
    private lazy var hud = HUDController(coordinator: self)
    private let pipeline = DictationPipeline()
    private let requestBuilder = OpenAIRequestBuilder()
    private let openAI = OpenAIClient()

    private var session: SpeechSession?
    private var elapsedTimer: Timer?
    private var startedAt: Date?
    private var dismissTask: Task<Void, Never>?
    private var pressBeganAt: Date?
    private var startedByCurrentPress = false

    var isRecording: Bool { phase == .recording }
    var isBusy: Bool { phase == .recording || phase == .transcribing }

    init(model: AppModel, hotKeys: HotKeyCenter) {
        self.model = model
        self.hotKeys = hotKeys
    }

    // MARK: - Hotkey entry points (tap = toggle, hold = push-to-talk)

    func hotKeyPressed() {
        switch phase {
        case .recording:
            startedByCurrentPress = false
            Task { await stopAndInsert() }
        case .idle, .notice:
            startedByCurrentPress = true
            pressBeganAt = Date()
            Task { await startRecording() }
        case .transcribing:
            break
        }
    }

    func hotKeyReleased() {
        defer {
            startedByCurrentPress = false
            pressBeganAt = nil
        }
        guard startedByCurrentPress,
              phase == .recording,
              let pressBeganAt,
              Date().timeIntervalSince(pressBeganAt) >= Self.pushToTalkThreshold else {
            return
        }
        Task { await stopAndInsert() }
    }

    func toggle() {
        if isRecording {
            Task { await stopAndInsert() }
        } else if phase == .idle || isNotice {
            Task { await startRecording() }
        }
    }

    private var isNotice: Bool {
        if case .notice = phase { return true }
        return false
    }

    // MARK: - Lifecycle

    func startRecording() async {
        guard phase == .idle || isNotice else { return }
        dismissTask?.cancel()

        guard await ensurePermissions() else { return }

        let session = SpeechSession()
        session.onPartial = { [weak self] text in
            self?.partialText = text
        }
        session.onLevel = { [weak self] level in
            self?.pushLevel(level)
        }
        session.onUnexpectedEnd = { [weak self] _ in
            guard let self, self.phase == .recording else { return }
            Task { await self.stopAndInsert() }
        }

        var audioFileURL: URL?
        // The Whisper engine transcribes from the captured file, so capture
        // even when the user doesn't keep audio in history (deleted after).
        if model.state.storeAudio || model.state.transcriptionEngine == "whisper",
           let history = model.history {
            audioFileURL = history.audioDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        }
        let contextualStrings = model.loadVocabulary().map(\.preferredSpelling)

        do {
            try session.start(
                localeIdentifier: model.state.localeIdentifier,
                preferOnDevice: model.state.preferOnDevice,
                contextualStrings: contextualStrings,
                audioFileURL: audioFileURL
            )
        } catch {
            showNotice(.error, message: error.localizedDescription, sound: "Basso")
            return
        }

        self.session = session
        partialText = ""
        levels = Array(repeating: 0, count: levels.count)
        elapsed = 0
        startedAt = Date()
        phase = .recording
        playSound("Pop")
        hud.show()
        hotKeys.registerEscape { [weak self] in
            self?.cancel()
        }
        startElapsedTimer()
    }

    /// Shows the HUD in a fake recording state — used by the screenshot
    /// tooling (`--show-overlay`); no audio session is started.
    func showHUDPreview() {
        partialText = "지금 말하는 내용이 실시간으로 표시됩니다"
        levels = (0..<levels.count).map { index in
            Float(0.15 + 0.7 * abs(sin(Double(index) * 0.55)))
        }
        elapsed = 7
        phase = .recording
        hud.show()
    }

    func stopAndInsert() async {
        guard phase == .recording else { return }
        guard let session else {
            // HUD preview has no live session.
            phase = .idle
            hud.hide()
            return
        }
        stopElapsedTimer()
        hotKeys.unregisterEscape()
        phase = .transcribing
        let stopRequestedAt = Date()

        var rawTranscript = (await session.finish()).trimmingCharacters(in: .whitespacesAndNewlines)
        let audioFileURL = session.audioFileURL
        self.session = nil

        if model.usesWhisper, let audioFileURL,
           FileManager.default.fileExists(atPath: audioFileURL.path) {
            // Whisper replaces the streaming transcript when it succeeds;
            // the Apple Speech text stays as the fallback.
            let whisperText = await model.whisper.transcribe(
                url: audioFileURL,
                localeIdentifier: model.state.localeIdentifier
            )
            if !whisperText.isEmpty {
                rawTranscript = whisperText
            }
        }

        if rawTranscript.isEmpty, let audioFileURL,
           FileManager.default.fileExists(atPath: audioFileURL.path) {
            // The streaming session can come back empty (notably speechd's
            // first session after launch). Re-recognize the captured audio.
            rawTranscript = (await SpeechSession.recognizeFile(
                at: audioFileURL,
                localeIdentifier: model.state.localeIdentifier,
                preferOnDevice: model.state.preferOnDevice
            )).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !rawTranscript.isEmpty else {
            if let audioFileURL {
                try? FileManager.default.removeItem(at: audioFileURL)
            }
            showNotice(.info, message: "No speech detected", sound: "Basso")
            return
        }

        if !model.state.storeAudio, let audioFileURL {
            // Captured only for the Whisper engine — don't keep it around.
            try? FileManager.default.removeItem(at: audioFileURL)
        }

        let vocabulary = model.loadVocabulary()
        let mode = model.state.selectedMode
        var result = pipeline.process(
            rawTranscript: rawTranscript,
            mode: mode,
            apiKeyState: .absent,
            vocabulary: vocabulary
        )
        if mode == .dictation {
            // Local-only path already final.
        } else if let apiKey = (try? model.keychain.read()) ?? nil, !apiKey.isEmpty {
            if let request = requestBuilder.build(
                mode: mode,
                rawTranscript: rawTranscript,
                vocabulary: vocabulary,
                manualModelOverride: model.state.manualModelOverride
            ) {
                do {
                    let transformed = try await openAI.transform(request, apiKey: apiKey)
                    result = DictationPipelineResult(
                        rawTranscript: rawTranscript,
                        finalOutput: transformed,
                        mode: mode,
                        status: .inserted
                    )
                } catch {
                    // Keep the locally cleaned fallback from `result`.
                }
            }
        }

        let delivery = deliverResult(result.finalOutput)
        let latency = Date().timeIntervalSince(stopRequestedAt)

        recordHistory(result: result, delivery: delivery, audioFileURL: audioFileURL)

        switch delivery {
        case .pasted:
            let modeSuffix = result.status == .postProcessingFailed ? " · AI fallback" : ""
            showNotice(.success, message: String(format: "Inserted · %.1fs%@", latency, modeSuffix), sound: "Tink")
        case .typed:
            showNotice(.success, message: String(format: "Typed · %.1fs", latency), sound: "Tink")
        case .clipboardOnly:
            showNotice(.info, message: "Copied — press ⌘V (enable Accessibility for auto-paste)", sound: "Tink")
        }
    }

    func cancel() {
        guard isBusy else { return }
        stopElapsedTimer()
        hotKeys.unregisterEscape()
        if let session {
            let audioFileURL = session.audioFileURL
            session.cancel()
            if let audioFileURL {
                try? FileManager.default.removeItem(at: audioFileURL)
            }
        }
        session = nil
        partialText = ""
        playSound("Basso")
        phase = .idle
        hud.hide()
    }

    // MARK: - Delivery

    private enum Delivery {
        case pasted
        case typed
        case clipboardOnly
    }

    private func deliverResult(_ text: String) -> Delivery {
        let pasteboard = MacPasteboardClient()
        let accessibilityTrusted = AXIsProcessTrusted()

        if model.state.typingModeEnabled && accessibilityTrusted {
            try? MacTextInsertionClient().type(text)
            return .typed
        }

        let clipboardSnapshot: Data? = model.state.restoreClipboard ? ((try? pasteboard.snapshot()) ?? nil) : nil
        try? pasteboard.setString(text)
        guard accessibilityTrusted else {
            return .clipboardOnly
        }
        try? MacTextInsertionClient().paste()
        if model.state.restoreClipboard {
            Task { @MainActor in
                // Give the frontmost app time to read the pasteboard first.
                try? await Task.sleep(nanoseconds: 700_000_000)
                try? MacPasteboardClient().restore(clipboardSnapshot)
            }
        }
        return .pasted
    }

    private func recordHistory(result: DictationPipelineResult, delivery: Delivery, audioFileURL: URL?) {
        guard let history = model.history else { return }
        let audioFileName: String
        if let audioFileURL, FileManager.default.fileExists(atPath: audioFileURL.path) {
            audioFileName = audioFileURL.lastPathComponent
        } else {
            audioFileName = ""
        }
        try? history.add(HistoryRecord(
            rawTranscript: result.rawTranscript,
            finalOutput: result.finalOutput,
            mode: result.mode,
            status: result.status,
            audioFileName: audioFileName
        ))
    }

    // MARK: - Permissions

    private func ensurePermissions() async -> Bool {
        model.refreshPermissions()
        if model.permissions.microphone != .granted {
            let granted = await SpeechPermissions.requestMicrophone()
            model.refreshPermissions()
            if !granted {
                showNotice(.error, message: "Microphone access needed — check System Settings", sound: "Basso")
                requestOnboarding?()
                return false
            }
        }
        if model.permissions.speechRecognition != .granted {
            let granted = await SpeechPermissions.requestSpeechRecognition()
            model.refreshPermissions()
            if !granted {
                showNotice(.error, message: "Speech Recognition access needed — check System Settings", sound: "Basso")
                requestOnboarding?()
                return false
            }
        }
        return true
    }

    // MARK: - Helpers

    private func startElapsedTimer() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
                if self.elapsed >= Self.maxRecordingSeconds, self.phase == .recording {
                    Task { await self.stopAndInsert() }
                }
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func pushLevel(_ level: Float) {
        guard phase == .recording else { return }
        var next = levels
        next.removeFirst()
        next.append(level)
        levels = next
    }

    private func showNotice(_ kind: NoticeKind, message: String, sound: String?) {
        phase = .notice(kind, message)
        hud.show()
        if let sound {
            playSound(sound)
        }
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard let self, !Task.isCancelled else { return }
            if case .notice = self.phase {
                self.phase = .idle
                self.hud.hide()
            }
        }
    }

    private func playSound(_ name: String) {
        guard model.state.playSounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
