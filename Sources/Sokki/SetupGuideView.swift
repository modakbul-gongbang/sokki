import AppKit
import SwiftUI
import SokkiCore

/// The setup guide: grant permissions, pick a language, try a dictation.
/// One view serves both the first-run "Welcome to Sokki" window and the
/// Setup tab in Settings, so the two surfaces can't drift apart.
struct SetupGuideView: View {
    @ObservedObject var model: AppModel
    /// Set when shown as the first-run onboarding window; nil inside Settings.
    var onDone: (() -> Void)?

    @State private var testText = ""

    private var shortcutDisplay: String {
        KeyboardShortcut.parse(model.state.globalShortcut)?.compactDisplay ?? model.state.globalShortcut
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white, .tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sokki")
                            .font(.title2.bold())
                        Text("Press \(shortcutDisplay) anywhere, speak, press it again — your words appear at the cursor.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("1. Grant permissions") {
                PermissionsSection(model: model)
                Text("Microphone + Speech Recognition are needed to dictate. Accessibility lets Sokki paste the result directly at your cursor — without it, results are copied to the clipboard instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("2. Choose your dictation language") {
                Picker("", selection: $model.state.localeIdentifier) {
                    ForEach(DictationLanguage.options, id: \.id) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Section("3. Try it here") {
                Text("Click into the field below, press \(shortcutDisplay), say something, then press \(shortcutDisplay) again. Hold-to-talk also works: keep it pressed while speaking and release.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $testText)
                    .font(.body)
                    .frame(height: 64)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.quaternary, lineWidth: 1)
                    )
            }
            Section {
                HStack {
                    Text(model.permissions.canDictate
                         ? "You're ready to dictate."
                         : "Microphone + Speech Recognition are required to start.")
                        .font(.caption)
                        .foregroundStyle(model.permissions.canDictate ? .green : .secondary)
                    if let onDone {
                        Spacer()
                        Button("Start using Sokki") {
                            model.state.hasCompletedOnboarding = true
                            onDone()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
