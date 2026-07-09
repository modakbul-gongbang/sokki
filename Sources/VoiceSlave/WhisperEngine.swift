import Foundation
import VoiceSlaveCore
import WhisperKit
import os

private let whisperLog = Logger(subsystem: "com.hoyeon.VoiceSlave", category: "whisper")

/// Moves the non-Sendable WhisperKit pipeline across the actor boundary once,
/// right after construction — safe because nothing else references it yet.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
}

/// Downloadable Whisper model pack (large-v3 turbo via WhisperKit CoreML).
/// Used as the final-transcript engine: the live HUD still streams partials
/// through Apple Speech, and when this engine is selected and ready the
/// captured audio is re-transcribed with Whisper for the inserted text.
@MainActor
final class WhisperEngine: ObservableObject {
    enum ModelState: Equatable {
        case notDownloaded
        case downloading(Double)      // 0...1
        case downloaded               // on disk, not loaded yet
        case loading
        case ready
        case failed(String)
    }

    static let variant = WhisperModelDefaults.defaultModel
    @Published private(set) var state: ModelState = .notDownloaded

    private var pipe: WhisperKit?
    private var loadTask: Task<Void, Never>?

    /// Everything WhisperKit downloads lives under this folder so a single
    /// delete removes the pack.
    private let downloadBase: URL

    init() {
        let root = (try? ApplicationSupport.defaultRoot())
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("VoiceSlave")
        downloadBase = root.appendingPathComponent("WhisperModels", isDirectory: true)
        state = modelFolder != nil ? .downloaded : .notDownloaded
    }

    var isReady: Bool { state == .ready }

    /// Model size on disk, "" when absent.
    var modelSizeDescription: String {
        guard let folder = modelFolder,
              let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else {
            return ""
        }
        var total: Int64 = 0
        for case let file as URL in files {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    /// WhisperKit stores the pack at <base>/models/<repo>/<variant-folder>.
    private var modelFolder: URL? {
        let modelsRoot = downloadBase
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: modelsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }
        return children.first { $0.lastPathComponent.contains(Self.variant) }
    }

    func download() {
        guard case .notDownloaded = state else { return }
        state = .downloading(0)
        whisperLog.info("model download start variant=\(Self.variant, privacy: .public)")
        Task { @MainActor in
            do {
                _ = try await WhisperKit.download(
                    variant: Self.variant,
                    downloadBase: downloadBase,
                    progressCallback: { @Sendable [weak self] progress in
                        let fraction = progress.fractionCompleted
                        Task { @MainActor [weak self] in
                            if case .downloading = self?.state {
                                self?.state = .downloading(fraction)
                            }
                        }
                    }
                )
                whisperLog.info("model download done")
                state = .downloaded
                loadIfNeeded()
            } catch {
                whisperLog.error("model download failed: \(error, privacy: .public)")
                state = .failed("Download failed: \(error.localizedDescription)")
            }
        }
    }

    /// Loads the model into memory (a few seconds) so dictation doesn't pay
    /// the load on first use.
    func loadIfNeeded() {
        guard state == .downloaded, loadTask == nil, let folder = modelFolder else { return }
        state = .loading
        whisperLog.info("model load start")
        loadTask = Task { @MainActor [weak self] in
            defer { self?.loadTask = nil }
            do {
                let boxed = try await Self.createPipe(modelFolder: folder.path)
                self?.pipe = boxed.value
                self?.state = .ready
                whisperLog.info("model load done")
            } catch {
                whisperLog.error("model load failed: \(error, privacy: .public)")
                self?.state = .failed("Couldn't load the model: \(error.localizedDescription)")
            }
        }
    }

    private nonisolated static func createPipe(modelFolder: String) async throws -> UncheckedSendableBox<WhisperKit> {
        let config = WhisperKitConfig(
            modelFolder: modelFolder,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false
        )
        return UncheckedSendableBox(value: try await WhisperKit(config))
    }

    func deleteModel() {
        pipe = nil
        loadTask?.cancel()
        loadTask = nil
        try? FileManager.default.removeItem(at: downloadBase)
        state = .notDownloaded
        whisperLog.info("model pack deleted")
    }

    /// Transcribes the captured audio file. Returns "" on any failure so the
    /// caller can keep the streaming transcript instead.
    func transcribe(url: URL, localeIdentifier: String) async -> String {
        guard let pipe else { return "" }
        var options = DecodingOptions()
        options.task = .transcribe
        options.chunkingStrategy = .vad
        switch localeIdentifier {
        case "auto":
            options.detectLanguage = true
        default:
            // "ko-KR" → "ko"
            options.language = String(localeIdentifier.prefix(2))
        }
        let text = await Self.runTranscription(
            UncheckedSendableBox(value: pipe),
            path: url.path,
            options: options
        )
        whisperLog.info("transcribe done length=\(text.count)")
        return text
    }

    private nonisolated static func runTranscription(
        _ box: UncheckedSendableBox<WhisperKit>,
        path: String,
        options: DecodingOptions
    ) async -> String {
        do {
            let results = try await box.value.transcribe(audioPath: path, decodeOptions: options)
            return results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            whisperLog.error("transcribe failed: \(error, privacy: .public)")
            return ""
        }
    }
}
