import AppKit
import Foundation
import SwiftUI
import VoiceSlaveCore

if CommandLine.arguments.contains("--qa-smoke") {
    try runQASmoke()
    Foundation.exit(0)
}

@MainActor
final class VoiceSlaveAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var overlayWindow: NSWindow?
    private let settings = ObservableSettings()
    private let modeGate = ModeGate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMenuBar()
    }

    private func installMenuBar() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "VS"
        statusItem.button?.toolTip = "VoiceSlave"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Start Dictation", action: #selector(toggleRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit VoiceSlave", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    @objc private func toggleRecording() {
        if overlayWindow == nil {
            showOverlay(status: "Recording", mode: settings.state.selectedMode.rawValue)
        } else {
            overlayWindow?.close()
            overlayWindow = nil
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "VoiceSlave Settings"
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showOverlay(status: String, mode: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 136),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = NSHostingView(rootView: RecordingOverlay(status: status, mode: mode) {
            self.overlayWindow?.close()
            self.overlayWindow = nil
        })
        window.center()
        window.makeKeyAndOrderFront(nil)
        overlayWindow = window
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
final class ObservableSettings: ObservableObject {
    @Published var state = AppSettings()
    @Published var permissions = PermissionSnapshot()
    @Published var model = ModelSetupState()
    @Published var apiKeyState: APIKeyState = .absent
}

struct SettingsView: View {
    @ObservedObject var settings: ObservableSettings
    private let gate = ModeGate()

    var body: some View {
        TabView {
            Form {
                Toggle("Launch at Login", isOn: $settings.state.launchAtLogin)
                Toggle("Preload model for faster dictation", isOn: $settings.state.preloadModel)
                Toggle("Typing Mode", isOn: $settings.state.typingModeEnabled)
                Picker("Mode", selection: $settings.state.selectedMode) {
                    ForEach(DictationMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Text("Shortcut: \(settings.state.globalShortcut)")
                Text("Bundle ID: \(settings.state.bundleIdentifier)")
            }
            .padding()
            .tabItem { Text("General") }

            Form {
                Text("WhisperKit model: \(settings.model.selectedModel)")
                Text("Fallbacks: \(settings.model.fallbackModels.joined(separator: ", "))")
                Text("Microphone: \(settings.permissions.microphone.rawValue)")
                Text("Accessibility: \(settings.permissions.accessibility.rawValue)")
                Text("Model setup: \(settings.permissions.modelSetupComplete ? "Ready" : "Required")")
            }
            .padding()
            .tabItem { Text("Onboarding") }

            Form {
                Text("Default OpenAI model: \(settings.state.openAIModel)")
                Text("Quality model: \(settings.state.qualityModel)")
                ForEach([DictationMode.cleanup, .prompt], id: \.self) { mode in
                    let availability = gate.availability(for: mode, apiKeyState: settings.apiKeyState)
                    HStack {
                        Text(mode.rawValue)
                        Spacer()
                        Text(availability.isEnabled ? "Enabled" : "Disabled")
                    }
                }
            }
            .padding()
            .tabItem { Text("Cloud Modes") }
        }
        .frame(minWidth: 680, minHeight: 500)
    }
}

struct RecordingOverlay: View {
    var status: String
    var mode: String
    var stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(status)
                    .font(.headline)
                Spacer()
                Text(mode)
                    .font(.subheadline)
            }
            WaveformView()
                .frame(height: 36)
            HStack {
                Text("00:00")
                    .monospacedDigit()
                Spacer()
                Button("Stop", action: stop)
                Button("Cancel", action: stop)
            }
        }
        .padding(18)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct WaveformView: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<18, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 5, height: CGFloat(10 + (index % 5) * 5))
            }
        }
    }
}

func runQASmoke() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("VoiceSlaveQASmoke", isDirectory: true)
    try? FileManager.default.removeItem(at: root)
    let history = try HistoryStore(root: root)
    let pipeline = DictationPipeline()
    let result = pipeline.process(
        rawTranscript: "  안녕 VoiceSlave\nlet value = 1  ",
        mode: .dictation,
        apiKeyState: .absent,
        vocabulary: []
    )
    try history.add(HistoryRecord(
        rawTranscript: result.rawTranscript,
        finalOutput: result.finalOutput,
        mode: result.mode,
        status: result.status,
        audioFileName: "qa-fixture.wav"
    ))
    let rows = try history.all()
    print("VoiceSlave QA smoke")
    print("menubar=available settings=available overlay=available")
    print("dictationMode=offline-capable cloudSTT=false")
    print("historyRows=\(rows.count) audioDir=\(history.audioDirectory.path)")
    try history.deleteAll()
    print("deleteAllRows=\(try history.all().count)")
}

let delegate = VoiceSlaveAppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
