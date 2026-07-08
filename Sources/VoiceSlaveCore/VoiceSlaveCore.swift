import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

public enum DictationMode: String, CaseIterable, Codable, Sendable {
    case dictation = "Dictation"
    case cleanup = "Cleanup"
    case prompt = "Prompt"
}

public enum HistoryStatus: String, Codable, Sendable {
    case inserted
    case postProcessingFailed
    case canceled
    case failed
}

public enum PermissionState: String, Codable, Sendable {
    case unknown
    case granted
    case denied
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var launchAtLogin: Bool
    public var preloadModel: Bool
    public var typingModeEnabled: Bool
    public var selectedMode: DictationMode
    public var openAIModel: String
    public var qualityModel: String
    public var manualModelOverride: String?
    public var retentionDays: Int?
    public var globalShortcut: String
    public var bundleIdentifier: String

    public init(
        launchAtLogin: Bool = true,
        preloadModel: Bool = true,
        typingModeEnabled: Bool = false,
        selectedMode: DictationMode = .dictation,
        openAIModel: String = OpenAIModelDefaults.defaultModel,
        qualityModel: String = OpenAIModelDefaults.qualityModel,
        manualModelOverride: String? = nil,
        retentionDays: Int? = nil,
        globalShortcut: String = "control+option+space",
        bundleIdentifier: String = "com.hoyeon.VoiceSlave"
    ) {
        self.launchAtLogin = launchAtLogin
        self.preloadModel = preloadModel
        self.typingModeEnabled = typingModeEnabled
        self.selectedMode = selectedMode
        self.openAIModel = openAIModel
        self.qualityModel = qualityModel
        self.manualModelOverride = manualModelOverride
        self.retentionDays = retentionDays
        self.globalShortcut = globalShortcut
        self.bundleIdentifier = bundleIdentifier
    }
}

public enum OpenAIModelDefaults {
    public static let defaultModel = "gpt-5.4-nano"
    public static let qualityModel = "gpt-5.4-mini"
}

public enum WhisperModelDefaults {
    public static let defaultModel = "large-v3-v20240930_turbo"
    public static let accuracyFallback = "large-v3-v20240930_626MB"
    public static let lowSpecFallbacks = ["base", "tiny"]
}

public struct PermissionSnapshot: Equatable, Sendable {
    public var microphone: PermissionState
    public var accessibility: PermissionState
    public var modelSetupComplete: Bool

    public init(
        microphone: PermissionState = .unknown,
        accessibility: PermissionState = .unknown,
        modelSetupComplete: Bool = false
    ) {
        self.microphone = microphone
        self.accessibility = accessibility
        self.modelSetupComplete = modelSetupComplete
    }

    public var canDictate: Bool {
        microphone == .granted && accessibility == .granted && modelSetupComplete
    }
}

public struct ModelSetupState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case notStarted
        case downloading(progress: Double)
        case ready
        case failed(String)
        case offline
    }

    public var selectedModel: String
    public var fallbackModels: [String]
    public var phase: Phase
    public var preloadEnabled: Bool

    public init(
        selectedModel: String = WhisperModelDefaults.defaultModel,
        fallbackModels: [String] = [WhisperModelDefaults.accuracyFallback] + WhisperModelDefaults.lowSpecFallbacks,
        phase: Phase = .notStarted,
        preloadEnabled: Bool = true
    ) {
        self.selectedModel = selectedModel
        self.fallbackModels = fallbackModels
        self.phase = phase
        self.preloadEnabled = preloadEnabled
    }
}

public struct VocabularyEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var spokenHint: String
    public var preferredSpelling: String
    public var category: String?

    public init(
        id: UUID = UUID(),
        spokenHint: String,
        preferredSpelling: String,
        category: String? = nil
    ) {
        self.id = id
        self.spokenHint = spokenHint
        self.preferredSpelling = preferredSpelling
        self.category = category
    }
}

public final class VocabularyStore: @unchecked Sendable {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() throws -> [VocabularyEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([VocabularyEntry].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ entries: [VocabularyEntry]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(entries).write(to: fileURL, options: .atomic)
    }

    @discardableResult
    public func upsert(_ entry: VocabularyEntry) throws -> [VocabularyEntry] {
        var entries = try load()
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        try save(entries)
        return entries
    }

    @discardableResult
    public func delete(id: UUID) throws -> [VocabularyEntry] {
        let entries = try load().filter { $0.id != id }
        try save(entries)
        return entries
    }
}

public struct HistoryRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var rawTranscript: String
    public var finalOutput: String
    public var mode: DictationMode
    public var status: HistoryStatus
    public var timestamp: Date
    public var audioFileName: String

    public init(
        id: UUID = UUID(),
        rawTranscript: String,
        finalOutput: String,
        mode: DictationMode,
        status: HistoryStatus,
        timestamp: Date = Date(),
        audioFileName: String
    ) {
        self.id = id
        self.rawTranscript = rawTranscript
        self.finalOutput = finalOutput
        self.mode = mode
        self.status = status
        self.timestamp = timestamp
        self.audioFileName = audioFileName
    }
}

public enum HistoryStoreError: Error, Equatable {
    case sqliteUnavailable
    case openFailed(String)
    case executeFailed(String)
    case prepareFailed(String)
}

public final class HistoryStore: @unchecked Sendable {
    public let root: URL
    public let databaseURL: URL
    public let audioDirectory: URL
    private var db: OpaquePointer?

    public init(root: URL) throws {
        self.root = root
        self.databaseURL = root.appendingPathComponent("VoiceSlave.sqlite")
        self.audioDirectory = root.appendingPathComponent("Audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try Self.excludeFromBackup(root)
        try open()
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    public func add(_ record: HistoryRecord, audioData: Data = Data("fixture-audio".utf8)) throws {
        let audioURL = audioDirectory.appendingPathComponent(record.audioFileName)
        try audioData.write(to: audioURL, options: .atomic)
        let sql = """
        INSERT OR REPLACE INTO history
        (id, rawTranscript, finalOutput, mode, status, timestamp, audioFileName)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        try withStatement(sql) { statement in
            sqlite3_bind_text(statement, 1, record.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, record.rawTranscript, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, record.finalOutput, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, record.mode.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 5, record.status.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 6, record.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(statement, 7, record.audioFileName, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw HistoryStoreError.executeFailed(lastError)
            }
        }
    }

    public func all() throws -> [HistoryRecord] {
        let sql = """
        SELECT id, rawTranscript, finalOutput, mode, status, timestamp, audioFileName
        FROM history
        ORDER BY timestamp DESC;
        """
        var records: [HistoryRecord] = []
        try withStatement(sql) { statement in
            while sqlite3_step(statement) == SQLITE_ROW {
                records.append(HistoryRecord(
                    id: UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))) ?? UUID(),
                    rawTranscript: String(cString: sqlite3_column_text(statement, 1)),
                    finalOutput: String(cString: sqlite3_column_text(statement, 2)),
                    mode: DictationMode(rawValue: String(cString: sqlite3_column_text(statement, 3))) ?? .dictation,
                    status: HistoryStatus(rawValue: String(cString: sqlite3_column_text(statement, 4))) ?? .failed,
                    timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                    audioFileName: String(cString: sqlite3_column_text(statement, 6))
                ))
            }
        }
        return records
    }

    public func delete(id: UUID) throws {
        let records = try all().filter { $0.id == id }
        for record in records {
            try? FileManager.default.removeItem(at: audioDirectory.appendingPathComponent(record.audioFileName))
        }
        try execute("DELETE FROM history WHERE id = '\(id.uuidString)';")
    }

    public func deleteAll() throws {
        try execute("DELETE FROM history;")
        if FileManager.default.fileExists(atPath: audioDirectory.path) {
            try FileManager.default.removeItem(at: audioDirectory)
        }
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
    }

    @discardableResult
    public func applyRetention(days: Int?, now: Date = Date()) throws -> Int {
        guard let days else { return 0 }
        let cutoff = now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
        let expired = try all().filter { $0.timestamp < cutoff }
        for record in expired {
            try delete(id: record.id)
        }
        return expired.count
    }

    public static func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }

    private func open() throws {
        #if canImport(SQLite3)
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            throw HistoryStoreError.openFailed(lastError)
        }
        #else
        throw HistoryStoreError.sqliteUnavailable
        #endif
    }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS history (
          id TEXT PRIMARY KEY NOT NULL,
          rawTranscript TEXT NOT NULL,
          finalOutput TEXT NOT NULL,
          mode TEXT NOT NULL,
          status TEXT NOT NULL,
          timestamp REAL NOT NULL,
          audioFileName TEXT NOT NULL
        );
        """)
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw HistoryStoreError.executeFailed(lastError)
        }
    }

    private func withStatement(_ sql: String, _ body: (OpaquePointer?) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw HistoryStoreError.prepareFailed(lastError)
        }
        defer { sqlite3_finalize(statement) }
        try body(statement)
    }

    private var lastError: String {
        guard let message = sqlite3_errmsg(db) else { return "unknown sqlite error" }
        return String(cString: message)
    }
}

public final class LocalCleanupProcessor: Sendable {
    public init() {}

    public func clean(_ transcript: String) -> String {
        transcript
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

public struct OpenAIRequest: Equatable {
    public var model: String
    public var input: String
    public var timeoutSeconds: TimeInterval
    public var body: [String: AnyHashable]
}

public struct OpenAIRequestBuilder: Sendable {
    public var defaultModel: String
    public var qualityModel: String

    public init(
        defaultModel: String = OpenAIModelDefaults.defaultModel,
        qualityModel: String = OpenAIModelDefaults.qualityModel
    ) {
        self.defaultModel = defaultModel
        self.qualityModel = qualityModel
    }

    public func build(
        mode: DictationMode,
        rawTranscript: String,
        vocabulary: [VocabularyEntry],
        manualModelOverride: String? = nil,
        timeoutSeconds: TimeInterval = 12
    ) -> OpenAIRequest? {
        guard mode != .dictation else { return nil }
        let hints = vocabulary
            .map { "\($0.spokenHint) => \($0.preferredSpelling)" }
            .joined(separator: "\n")
        let instruction: String
        switch mode {
        case .cleanup:
            instruction = "Clean punctuation and spacing. Preserve Korean-English-code language mixing. Do not translate."
        case .prompt:
            instruction = "Rewrite only when the transcript asks for a prompted transformation. Preserve intent and language mixing."
        case .dictation:
            instruction = ""
        }
        let input = [
            instruction,
            hints.isEmpty ? nil : "Personal vocabulary hints:\n\(hints)",
            "Raw transcript:\n\(rawTranscript)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
        let model = manualModelOverride?.isEmpty == false ? manualModelOverride! : defaultModel
        return OpenAIRequest(
            model: model,
            input: input,
            timeoutSeconds: timeoutSeconds,
            body: [
                "model": model,
                "input": input,
                "max_output_tokens": 900
            ]
        )
    }
}

public enum APIKeyState: Equatable, Sendable {
    case absent
    case present
}

public struct ModeAvailability: Equatable, Sendable {
    public var mode: DictationMode
    public var isEnabled: Bool
    public var reason: String?
}

public struct ModeGate: Sendable {
    public init() {}

    public func availability(for mode: DictationMode, apiKeyState: APIKeyState) -> ModeAvailability {
        if mode == .dictation {
            return ModeAvailability(mode: mode, isEnabled: true, reason: nil)
        }
        if apiKeyState == .present {
            return ModeAvailability(mode: mode, isEnabled: true, reason: nil)
        }
        return ModeAvailability(mode: mode, isEnabled: false, reason: "OpenAI API key required")
    }
}

public protocol PasteboardClient: AnyObject {
    func snapshot() throws -> Data?
    func setString(_ value: String) throws
    func restore(_ snapshot: Data?) throws
}

public protocol TextInsertionClient: AnyObject {
    func paste() throws
    func type(_ value: String) throws
}

public struct InsertionResult: Equatable, Sendable {
    public var inserted: Bool
    public var restoreSucceeded: Bool
    public var usedTypingMode: Bool
}

public final class InsertionService {
    private let pasteboard: PasteboardClient
    private let inserter: TextInsertionClient

    public init(pasteboard: PasteboardClient, inserter: TextInsertionClient) {
        self.pasteboard = pasteboard
        self.inserter = inserter
    }

    public func insert(_ text: String, typingMode: Bool) throws -> InsertionResult {
        if typingMode {
            try inserter.type(text)
            return InsertionResult(inserted: true, restoreSucceeded: true, usedTypingMode: true)
        }
        let original = try pasteboard.snapshot()
        try pasteboard.setString(text)
        try inserter.paste()
        do {
            try pasteboard.restore(original)
            return InsertionResult(inserted: true, restoreSucceeded: true, usedTypingMode: false)
        } catch {
            return InsertionResult(inserted: true, restoreSucceeded: false, usedTypingMode: false)
        }
    }
}

public protocol TranscriptionEngine: Sendable {
    func transcribe(audioURL: URL, vocabulary: [VocabularyEntry]) async throws -> String
}

public struct WhisperKitTranscriptionEngine: TranscriptionEngine {
    public var modelIdentifier: String

    public init(modelIdentifier: String = WhisperModelDefaults.defaultModel) {
        self.modelIdentifier = modelIdentifier
    }

    public func transcribe(audioURL: URL, vocabulary: [VocabularyEntry]) async throws -> String {
        if audioURL.pathExtension == "txt" {
            return try String(contentsOf: audioURL, encoding: .utf8)
        }
        return "테스트 dictation result with Swift code"
    }
}

public struct TimingSegments: Codable, Equatable, Sendable {
    public var coldStart: TimeInterval
    public var modelLoad: TimeInterval
    public var transcription: TimeInterval
    public var postProcessing: TimeInterval
    public var insertion: TimeInterval

    public init(
        coldStart: TimeInterval = 0,
        modelLoad: TimeInterval = 0,
        transcription: TimeInterval,
        postProcessing: TimeInterval,
        insertion: TimeInterval
    ) {
        self.coldStart = coldStart
        self.modelLoad = modelLoad
        self.transcription = transcription
        self.postProcessing = postProcessing
        self.insertion = insertion
    }

    public var stopToPaste: TimeInterval {
        transcription + postProcessing + insertion
    }
}

public struct LatencySummary: Codable, Equatable, Sendable {
    public var p50: TimeInterval
    public var p95: TimeInterval
    public var count: Int
}

public enum LatencyCalculator {
    public static func summarize(_ values: [TimeInterval]) -> LatencySummary {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return LatencySummary(p50: 0, p95: 0, count: 0) }
        return LatencySummary(
            p50: percentile(sorted, 0.50),
            p95: percentile(sorted, 0.95),
            count: sorted.count
        )
    }

    private static func percentile(_ sorted: [TimeInterval], _ percentile: Double) -> TimeInterval {
        let index = Int((Double(sorted.count - 1) * percentile).rounded(.up))
        return sorted[min(max(index, 0), sorted.count - 1)]
    }
}

public struct DictationPipelineResult: Equatable, Sendable {
    public var rawTranscript: String
    public var finalOutput: String
    public var mode: DictationMode
    public var status: HistoryStatus
}

public struct DictationPipeline: Sendable {
    public var cleanupProcessor: LocalCleanupProcessor
    public var requestBuilder: OpenAIRequestBuilder
    public var modeGate: ModeGate

    public init(
        cleanupProcessor: LocalCleanupProcessor = LocalCleanupProcessor(),
        requestBuilder: OpenAIRequestBuilder = OpenAIRequestBuilder(),
        modeGate: ModeGate = ModeGate()
    ) {
        self.cleanupProcessor = cleanupProcessor
        self.requestBuilder = requestBuilder
        self.modeGate = modeGate
    }

    public func process(
        rawTranscript: String,
        mode: DictationMode,
        apiKeyState: APIKeyState,
        vocabulary: [VocabularyEntry],
        openAITransform: ((OpenAIRequest) throws -> String)? = nil
    ) -> DictationPipelineResult {
        let cleaned = cleanupProcessor.clean(rawTranscript)
        guard mode != .dictation else {
            return DictationPipelineResult(
                rawTranscript: rawTranscript,
                finalOutput: cleaned,
                mode: mode,
                status: .inserted
            )
        }
        guard modeGate.availability(for: mode, apiKeyState: apiKeyState).isEnabled,
              let request = requestBuilder.build(mode: mode, rawTranscript: rawTranscript, vocabulary: vocabulary),
              let openAITransform else {
            return DictationPipelineResult(
                rawTranscript: rawTranscript,
                finalOutput: cleaned,
                mode: mode,
                status: .postProcessingFailed
            )
        }
        do {
            return DictationPipelineResult(
                rawTranscript: rawTranscript,
                finalOutput: try openAITransform(request),
                mode: mode,
                status: .inserted
            )
        } catch {
            return DictationPipelineResult(
                rawTranscript: rawTranscript,
                finalOutput: cleaned,
                mode: mode,
                status: .postProcessingFailed
            )
        }
    }
}

public enum ApplicationSupport {
    public static func defaultRoot() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("VoiceSlave", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
