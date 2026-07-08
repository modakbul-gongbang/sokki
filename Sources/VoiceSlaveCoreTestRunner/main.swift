import Foundation
import VoiceSlaveCore

struct TestFailure: Error, CustomStringConvertible {
    var description: String
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw TestFailure(description: message)
    }
}

func temporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("VoiceSlaveTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

final class FakePasteboard: PasteboardClient {
    var currentString: String?
    var shouldFailRestore = false

    func snapshot() throws -> Data? {
        currentString?.data(using: .utf8)
    }

    func setString(_ value: String) throws {
        currentString = value
    }

    func restore(_ snapshot: Data?) throws {
        if shouldFailRestore {
            throw URLError(.cannotWriteToFile)
        }
        currentString = snapshot.flatMap { String(data: $0, encoding: .utf8) }
    }
}

final class FakeInserter: TextInsertionClient {
    var pasteCount = 0
    var typedText: String?

    func paste() throws {
        pasteCount += 1
    }

    func type(_ value: String) throws {
        typedText = value
    }
}

let tests: [(String, () throws -> Void)] = [
    ("local cleanup preserves Korean-English-code mixing", {
        let output = LocalCleanupProcessor().clean("  안녕 VoiceSlave\n\nlet value = 1  ")
        try require(output == "안녕 VoiceSlave\nlet value = 1", "cleanup output mismatch")
    }),
    ("mode gating keeps dictation local and cloud modes key-gated", {
        let gate = ModeGate()
        try require(gate.availability(for: .dictation, apiKeyState: .absent).isEnabled, "dictation should be enabled")
        try require(!gate.availability(for: .cleanup, apiKeyState: .absent).isEnabled, "cleanup should require key")
        try require(!gate.availability(for: .prompt, apiKeyState: .absent).isEnabled, "prompt should require key")
        try require(gate.availability(for: .cleanup, apiKeyState: .present).isEnabled, "cleanup should enable with key")
    }),
    ("OpenAI request excludes clipboard selected text cursor and app context", {
        let request = OpenAIRequestBuilder().build(
            mode: .cleanup,
            rawTranscript: "회의 말고 dictation 테스트",
            vocabulary: [VocabularyEntry(spokenHint: "보이스 슬레이브", preferredSpelling: "VoiceSlave")]
        )
        guard let request else { throw TestFailure(description: "request missing") }
        let body = String(describing: request.body)
        try require(request.model == "gpt-5.4-nano", "default model mismatch")
        try require(body.contains("회의 말고 dictation 테스트"), "raw transcript missing")
        try require(body.contains("VoiceSlave"), "vocabulary hint missing")
        try require(!body.localizedCaseInsensitiveContains("clipboard"), "clipboard leaked")
        try require(!body.localizedCaseInsensitiveContains("selected text"), "selected text leaked")
        try require(!body.localizedCaseInsensitiveContains("active app"), "active app leaked")
        try require(!body.localizedCaseInsensitiveContains("cursor surroundings"), "cursor surroundings leaked")
    }),
    ("dictation mode never builds OpenAI request", {
        try require(OpenAIRequestBuilder().build(mode: .dictation, rawTranscript: "local only", vocabulary: []) == nil, "dictation built cloud request")
    }),
    ("post-processing failure falls back to cleaned raw transcript", {
        let result = DictationPipeline().process(
            rawTranscript: "  원문 transcript  ",
            mode: .cleanup,
            apiKeyState: .present,
            vocabulary: [],
            openAITransform: { _ in throw URLError(.timedOut) }
        )
        try require(result.finalOutput == "원문 transcript", "fallback text mismatch")
        try require(result.status == .postProcessingFailed, "failure status mismatch")
    }),
    ("vocabulary persistence supports add edit delete", {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VocabularyStore(fileURL: root.appendingPathComponent("vocabulary.json"))
        var entry = VocabularyEntry(spokenHint: "오픈 에이아이", preferredSpelling: "OpenAI", category: "company")
        try store.upsert(entry)
        try require(try store.load() == [entry], "entry not saved")
        entry.preferredSpelling = "OpenAI API"
        try store.upsert(entry)
        try require(try store.load().first?.preferredSpelling == "OpenAI API", "entry not edited")
        try store.delete(id: entry.id)
        try require(try store.load().isEmpty, "entry not deleted")
    }),
    ("history SQLite stores deletes retains and excludes backup", {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try HistoryStore(root: root)
        let old = HistoryRecord(
            rawTranscript: "old",
            finalOutput: "old",
            mode: .dictation,
            status: .inserted,
            timestamp: Date(timeIntervalSince1970: 1),
            audioFileName: "old.wav"
        )
        let recent = HistoryRecord(
            rawTranscript: "new",
            finalOutput: "new",
            mode: .cleanup,
            status: .postProcessingFailed,
            timestamp: Date(),
            audioFileName: "new.wav"
        )
        try store.add(old)
        try store.add(recent)
        try require(try store.all().count == 2, "history row count mismatch")
        try require(FileManager.default.fileExists(atPath: store.audioDirectory.appendingPathComponent("new.wav").path), "audio fixture missing")
        try require(try store.applyRetention(days: 7) == 1, "retention did not delete old row")
        try require(try store.all().map(\.rawTranscript) == ["new"], "retention left wrong rows")
        let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        try require(values.isExcludedFromBackup == true, "backup exclusion missing")
        try store.delete(id: recent.id)
        try require(try store.all().isEmpty, "delete did not remove row")
    }),
    ("clipboard restore failure does not fail insertion", {
        let pasteboard = FakePasteboard()
        pasteboard.shouldFailRestore = true
        let inserter = FakeInserter()
        let result = try InsertionService(pasteboard: pasteboard, inserter: inserter).insert("hello", typingMode: false)
        try require(result.inserted, "insert failed")
        try require(!result.restoreSucceeded, "restore should fail separately")
        try require(pasteboard.currentString == "hello", "pasteboard text mismatch")
        try require(inserter.pasteCount == 1, "paste not invoked")
    }),
    ("typing mode bypasses clipboard", {
        let pasteboard = FakePasteboard()
        let inserter = FakeInserter()
        let result = try InsertionService(pasteboard: pasteboard, inserter: inserter).insert("typed", typingMode: true)
        try require(result.usedTypingMode, "typing mode not reported")
        try require(inserter.typedText == "typed", "typing text mismatch")
        try require(pasteboard.currentString == nil, "clipboard should be untouched")
    }),
    ("latency metrics calculate p50 and p95", {
        let summary = LatencyCalculator.summarize([0.7, 0.9, 1.1, 1.4, 1.8])
        try require(summary.count == 5, "latency count mismatch")
        try require(abs(summary.p50 - 1.1) < 0.001, "p50 mismatch")
        try require(abs(summary.p95 - 1.8) < 0.001, "p95 mismatch")
    }),
    ("permission snapshot blocks until ready", {
        try require(!PermissionSnapshot(microphone: .granted, accessibility: .denied, modelSetupComplete: true).canDictate, "should block without accessibility")
        try require(PermissionSnapshot(microphone: .granted, accessibility: .granted, modelSetupComplete: true).canDictate, "should allow ready state")
    }),
    ("model defaults use WhisperKit turbo class and fallbacks", {
        let state = ModelSetupState()
        try require(state.selectedModel == "large-v3-v20240930_turbo", "default WhisperKit model mismatch")
        try require(state.fallbackModels.contains("large-v3-v20240930_626MB"), "accuracy fallback missing")
        try require(state.fallbackModels.contains("tiny"), "debug fallback missing")
    })
]

var failures: [String] = []
for (name, test) in tests {
    do {
        try test()
        print("PASS \(name)")
    } catch {
        failures.append("FAIL \(name): \(error)")
    }
}

if failures.isEmpty {
    print("VoiceSlaveCoreTestRunner: \(tests.count) passed")
} else {
    for failure in failures {
        print(failure)
    }
    Foundation.exit(1)
}
