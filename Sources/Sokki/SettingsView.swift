import AppKit
import SwiftUI
import SokkiCore

enum SettingsTab: Hashable {
    case general
    case dictation
    case vocabulary
    case history
    case aiModes
    case setup
}

@MainActor
final class SettingsRouter: ObservableObject {
    @Published var tab: SettingsTab = .general
}

struct SettingsRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var router: SettingsRouter

    var body: some View {
        TabView(selection: $router.tab) {
            GeneralTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            DictationTab(model: model)
                .tabItem { Label("Dictation", systemImage: "mic") }
                .tag(SettingsTab.dictation)
            VocabularyTab(model: model)
                .tabItem { Label("Vocabulary", systemImage: "character.book.closed") }
                .tag(SettingsTab.vocabulary)
            HistoryTab(model: model)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(SettingsTab.history)
            AIModesTab(model: model)
                .tabItem { Label("AI Modes", systemImage: "sparkles") }
                .tag(SettingsTab.aiModes)
            SetupTab(model: model)
                .tabItem { Label("Setup", systemImage: "checkmark.shield") }
                .tag(SettingsTab.setup)
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Shortcut") {
                LabeledContent("Toggle dictation") {
                    HStack(spacing: 8) {
                        ShortcutRecorderView(shortcut: $model.state.globalShortcut)
                        Button("Reset") { model.resetShortcut() }
                    }
                }
                if !model.shortcutRegistrationStatus.isEmpty {
                    Text(model.shortcutRegistrationStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Tap to start/stop, or hold to talk and release to insert (push-to-talk). Press esc while recording to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Also trigger with the 🌐 fn key", isOn: $model.state.fnKeyTrigger)
                if !model.fnTriggerStatus.isEmpty {
                    Text(model.fnTriggerStatus)
                        .font(.caption)
                        .foregroundStyle(model.fnTriggerStatus.hasPrefix("Active") ? Color.secondary : Color.orange)
                    if !model.fnTriggerStatus.hasPrefix("Active") {
                        Button("Open Accessibility Settings") {
                            MacPermissionReader().openAccessibilitySettings()
                        }
                        Text("Already shows as enabled there? Remove Sokki from the list with − and add it back — reinstalling the app invalidates the old entry.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if model.state.fnKeyTrigger {
                    Text("Needs the same Accessibility permission as auto-paste. Also set System Settings → Keyboard → \"Press 🌐 key to\" to \"Do Nothing\" so pressing fn doesn't open the emoji picker or switch input sources. fn combos (fn+arrows, fn+F-keys) are ignored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Behavior") {
                Toggle("Launch at login", isOn: $model.state.launchAtLogin)
                if !model.launchAtLoginStatus.isEmpty {
                    Text(model.launchAtLoginStatus)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Toggle("Play sounds", isOn: $model.state.playSounds)
            }
            Section("Text insertion") {
                Picker("Insert method", selection: $model.state.typingModeEnabled) {
                    Text("Paste (fast, recommended)").tag(false)
                    Text("Type characters (for apps that block paste)").tag(true)
                }
                .pickerStyle(.radioGroup)
                Toggle("Restore previous clipboard after paste", isOn: $model.state.restoreClipboard)
                    .disabled(model.state.typingModeEnabled)
                Text(model.state.restoreClipboard
                     ? "Your clipboard is put back ~0.7s after pasting."
                     : "The dictated text stays on your clipboard after pasting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Dictation

private struct DictationTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Recognition") {
                Picker("Language", selection: $model.state.localeIdentifier) {
                    ForEach(DictationLanguage.options, id: \.id) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                Toggle("Prefer on-device recognition", isOn: $model.state.preferOnDevice)
                Text("On-device keeps audio private and works offline. If the language isn't available on-device, Apple's server recognition is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Engine") {
                EngineSection(model: model, whisper: model.whisper)
            }
            Section("Default mode") {
                Picker("Mode", selection: $model.state.selectedMode) {
                    ForEach(DictationMode.allCases, id: \.self) { mode in
                        Text(modeLabel(mode)).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                if model.apiKeyState == .absent {
                    Text("Cleanup and Prompt post-process with OpenAI and need an API key (AI Modes tab). Without one they fall back to local cleanup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Recording") {
                Toggle("Keep audio recordings in history", isOn: $model.state.storeAudio)
                Text("Recordings auto-stop after \(Int(RecordingCoordinator.maxRecordingSeconds / 60)) minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func modeLabel(_ mode: DictationMode) -> String {
        switch mode {
        case .dictation: return "Dictation — local, fastest"
        case .cleanup: return "Cleanup — AI fixes punctuation & spacing"
        case .prompt: return "Prompt — AI transforms on request"
        }
    }
}

/// Engine picker + Whisper model-pack download/management.
private struct EngineSection: View {
    @ObservedObject var model: AppModel
    @ObservedObject var whisper: WhisperEngine

    var body: some View {
        Picker("Transcription engine", selection: $model.state.transcriptionEngine) {
            Text("Apple Speech — instant, built-in").tag("apple")
            Text("Whisper large-v3 turbo — best quality, needs model pack").tag("whisper")
        }
        .pickerStyle(.radioGroup)

        if model.state.transcriptionEngine == "whisper" {
            switch whisper.state {
            case .notDownloaded:
                LabeledContent("Model pack") {
                    Button("Download (≈1.6 GB)") { whisper.download() }
                }
                Text("Until the pack is downloaded, dictation falls back to Apple Speech. The download is one-time and stays on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress) {
                        Text("Downloading Whisper large-v3 turbo… \(Int(progress * 100))%")
                            .font(.caption)
                    }
                }
            case .downloaded, .loading:
                LabeledContent("Model pack") {
                    Text("Loading model…")
                        .foregroundStyle(.secondary)
                }
            case .ready:
                LabeledContent("Model pack") {
                    HStack(spacing: 8) {
                        Label("Ready\(whisper.modelSizeDescription.isEmpty ? "" : " · \(whisper.modelSizeDescription)")", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Delete") { whisper.deleteModel() }
                    }
                }
                Text("Live text in the recording pill still streams via Apple Speech; the inserted result is re-transcribed with Whisper for quality — noticeably better for Korean-English mixed speech.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                LabeledContent("Model pack") {
                    Button("Retry download") {
                        whisper.deleteModel()
                        whisper.download()
                    }
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Vocabulary

private struct VocabularyTab: View {
    @ObservedObject var model: AppModel
    @State private var entries: [VocabularyEntry] = []
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Text("Fix words the recognizer keeps getting wrong. Matching is case-insensitive; the replacement is inserted exactly as written. Entries are also fed to the recognizer as vocabulary hints.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Replacements") {
                if entries.isEmpty {
                    Text("No entries yet — e.g. “속기” → “Sokki”")
                        .foregroundStyle(.secondary)
                }
                ForEach($entries) { $entry in
                    HStack(spacing: 8) {
                        TextField("Heard as…", text: $entry.spokenHint)
                            .textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        TextField("Replace with…", text: $entry.preferredSpelling)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            entries.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button {
                    entries.append(VocabularyEntry(spokenHint: "", preferredSpelling: ""))
                } label: {
                    Label("Add replacement", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            guard !loaded else { return }
            entries = model.loadVocabulary()
            loaded = true
        }
        .onChange(of: entries) { _, newValue in
            try? model.vocabulary.save(newValue)
        }
    }
}

// MARK: - History

private struct HistoryTab: View {
    @ObservedObject var model: AppModel
    @State private var records: [HistoryRecord] = []
    @State private var query = ""

    private var filtered: [HistoryRecord] {
        guard !query.isEmpty else { return records }
        return records.filter {
            $0.finalOutput.localizedCaseInsensitiveContains(query)
                || $0.rawTranscript.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search history", text: $query)
                    .textFieldStyle(.plain)
                Button("Refresh") { reload() }
            }
            .padding(10)
            Divider()
            if filtered.isEmpty {
                Spacer()
                Text(records.isEmpty ? "No dictations yet" : "No matches")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filtered) { record in
                    HistoryRow(record: record) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.finalOutput, forType: .string)
                    } onDelete: {
                        try? model.history?.delete(id: record.id)
                        reload()
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                Picker("Keep for", selection: retentionBinding) {
                    Text("Forever").tag(-1)
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .frame(maxWidth: 220)
                Spacer()
                Button("Reveal Audio Folder") {
                    if let history = model.history {
                        NSWorkspace.shared.activateFileViewerSelecting([history.audioDirectory])
                    }
                }
                Button("Delete All", role: .destructive) {
                    try? model.history?.deleteAll()
                    reload()
                }
            }
            .padding(10)
        }
        .onAppear { reload() }
    }

    private var retentionBinding: Binding<Int> {
        Binding(
            get: { model.state.retentionDays ?? -1 },
            set: { newValue in
                model.state.retentionDays = newValue == -1 ? nil : newValue
                model.applyRetention()
                reload()
            }
        )
    }

    private func reload() {
        records = (try? model.history?.all()) ?? []
    }
}

private struct HistoryRow: View {
    let record: HistoryRecord
    var onCopy: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.finalOutput)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(record.timestamp, format: .dateTime.month().day().hour().minute())
                    Text(record.mode.rawValue)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.quaternary))
                    if record.status == .postProcessingFailed {
                        Text("AI fallback")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy")
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
        .padding(.vertical, 3)
    }
}

// MARK: - AI Modes

private struct AIModesTab: View {
    @ObservedObject var model: AppModel
    @State private var keyInput = ""
    @State private var statusMessage = ""

    var body: some View {
        Form {
            Section("OpenAI API key") {
                LabeledContent("Status") {
                    if model.apiKeyState == .present {
                        Label("Saved in Keychain", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not set", systemImage: "circle")
                            .foregroundStyle(.secondary)
                    }
                }
                SecureField("sk-…", text: $keyInput)
                HStack {
                    Button("Save to Keychain") {
                        do {
                            try model.keychain.save(keyInput.trimmingCharacters(in: .whitespacesAndNewlines))
                            keyInput = ""
                            statusMessage = "Saved."
                        } catch {
                            statusMessage = "Save failed: \(error)"
                        }
                        model.refreshAPIKeyState()
                    }
                    .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove", role: .destructive) {
                        try? model.keychain.delete()
                        statusMessage = "Removed."
                        model.refreshAPIKeyState()
                    }
                    .disabled(model.apiKeyState == .absent)
                }
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("The key is stored only in your macOS Keychain and used only for Cleanup/Prompt modes. Dictation mode never touches the network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Model") {
                TextField("OpenAI model", text: $model.state.openAIModel)
                Text("Used for Cleanup and Prompt modes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Mode availability") {
                ForEach([DictationMode.cleanup, .prompt], id: \.self) { mode in
                    let availability = ModeGate().availability(for: mode, apiKeyState: model.apiKeyState)
                    LabeledContent(mode.rawValue) {
                        if availability.isEnabled {
                            Label("Enabled", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label(availability.reason ?? "Disabled", systemImage: "lock")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Setup / permissions

struct SetupTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SetupGuideView(model: model, onDone: nil)
    }
}

struct PermissionsSection: View {
    @ObservedObject var model: AppModel
    private let reader = MacPermissionReader()

    var body: some View {
        PermissionRow(
            title: "Microphone",
            icon: "mic.fill",
            state: model.permissions.microphone,
            requestTitle: "Allow…"
        ) {
            Task {
                _ = await SpeechPermissions.requestMicrophone()
                model.refreshPermissions()
                // The system permission dialog deactivated us; come back so
                // the window doesn't vanish behind other apps mid-setup.
                NSApp.activate(ignoringOtherApps: true)
            }
        } openSettings: {
            reader.openMicrophoneSettings()
        }
        PermissionRow(
            title: "Speech Recognition",
            icon: "waveform",
            state: model.permissions.speechRecognition,
            requestTitle: "Allow…"
        ) {
            Task {
                _ = await SpeechPermissions.requestSpeechRecognition()
                model.refreshPermissions()
                NSApp.activate(ignoringOtherApps: true)
            }
        } openSettings: {
            reader.openSpeechRecognitionSettings()
        }
        PermissionRow(
            title: "Accessibility (auto-paste)",
            icon: "accessibility",
            state: model.permissions.accessibility,
            requestTitle: "Grant…"
        ) {
            reader.promptForAccessibility()
            reader.openAccessibilitySettings()
        } openSettings: {
            reader.openAccessibilitySettings()
        }
        .task {
            // Accessibility trust can change outside the app; poll while visible
            // and pull the user back from System Settings once it's granted.
            var wasGranted = model.permissions.accessibility == .granted
            while !Task.isCancelled {
                model.refreshPermissions()
                let granted = model.permissions.accessibility == .granted
                if granted && !wasGranted {
                    NSApp.activate(ignoringOtherApps: true)
                }
                wasGranted = granted
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
        if model.permissions.accessibility == .denied {
            Text("Shows as enabled in System Settings but still not working? Remove Sokki from the Accessibility list with − and add it back — reinstalling the app invalidates the old entry.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let icon: String
    let state: PermissionState
    let requestTitle: String
    var request: () -> Void
    var openSettings: () -> Void

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            switch state {
            case .granted:
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .denied:
                Label("Denied", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Button("Open Settings") { openSettings() }
            case .unknown:
                Button(requestTitle) { request() }
            }
        }
    }
}

// MARK: - Shortcut recorder

struct ShortcutRecorderView: View {
    @Binding var shortcut: String
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? endRecording() : beginRecording()
        } label: {
            Text(isRecording ? "Press shortcut… (esc to cancel)" : displayText)
                .frame(minWidth: 150)
        }
        .onDisappear { endRecording() }
    }

    private var displayText: String {
        KeyboardShortcut.parse(shortcut)?.compactDisplay ?? shortcut
    }

    private func beginRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 && event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                endRecording()
                return nil
            }
            if let canonical = KeyboardShortcut.canonicalString(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags
            ) {
                shortcut = canonical
                endRecording()
                return nil
            }
            return nil
        }
    }

    private func endRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
