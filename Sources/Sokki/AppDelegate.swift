import AppKit
import SwiftUI
import SokkiCore

@MainActor
final class SokkiAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    let model = AppModel()
    private let hotKeys = HotKeyCenter()
    private let fnMonitor = FnKeyMonitor()
    private lazy var coordinator = RecordingCoordinator(model: model, hotKeys: hotKeys)
    private let router = SettingsRouter()
    private let launchArguments = Set(CommandLine.arguments.dropFirst())
    private var fnPermissionWaiter: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        coordinator.onPhaseChange = { [weak self] phase in
            self?.updateStatusIcon(phase)
        }
        coordinator.requestOnboarding = { [weak self] in
            self?.openOnboarding()
        }
        model.onShortcutChanged = { [weak self] shortcutText in
            self?.installHotKey(shortcutText)
        }
        model.onFnTriggerChanged = { [weak self] enabled in
            self?.applyFnTrigger(enabled)
        }
        fnMonitor.onPress = { [weak self] in self?.coordinator.hotKeyPressed() }
        fnMonitor.onRelease = { [weak self] in self?.coordinator.hotKeyReleased() }
        fnMonitor.onCombo = { [weak self] in self?.coordinator.cancel() }

        installMenuBar()
        installHotKey(model.state.globalShortcut)
        applyFnTrigger(model.state.fnKeyTrigger)
        updateStatusIcon(.idle)

        if launchArguments.contains("--show-settings") {
            openSettings()
        }
        if launchArguments.contains("--show-overlay") {
            coordinator.showHUDPreview()
        }
        if launchArguments.contains("--show-onboarding") {
            openOnboarding()
        }
        if !model.state.hasCompletedOnboarding
            && launchArguments.isDisjoint(with: ["--show-settings", "--show-overlay", "--show-onboarding"]) {
            openOnboarding()
        }
    }

    // MARK: - Hotkey

    private func installHotKey(_ shortcutText: String) {
        guard let shortcut = KeyboardShortcut.parse(shortcutText) else {
            hotKeys.unregisterMain()
            model.shortcutRegistrationStatus = "Invalid shortcut — try e.g. control+option+space"
            return
        }
        let registered = hotKeys.registerMain(
            shortcut,
            onPress: { [weak self] in self?.coordinator.hotKeyPressed() },
            onRelease: { [weak self] in self?.coordinator.hotKeyReleased() }
        )
        model.shortcutRegistrationStatus = registered
            ? "Active: \(shortcut.compactDisplay)"
            : "Couldn't register \(shortcut.compactDisplay) — it may be taken by another app"
    }

    private func applyFnTrigger(_ enabled: Bool) {
        fnPermissionWaiter?.invalidate()
        fnPermissionWaiter = nil
        guard enabled else {
            fnMonitor.stop()
            model.fnTriggerStatus = ""
            return
        }
        if FnKeyMonitor.hasPermission {
            model.fnTriggerStatus = fnMonitor.start()
                ? "Active: 🌐 fn (tap to toggle, hold to talk)"
                : "Couldn't start the fn key listener — try relaunching Sokki"
        } else {
            MacPermissionReader().promptForAccessibility()
            model.fnTriggerStatus = "Waiting for Accessibility permission — the fn trigger activates automatically once granted"
            startFnPermissionWaiter()
        }
    }

    /// Accessibility trust is often granted (or re-granted after a reinstall)
    /// while the app is already running; poll until it appears so the fn
    /// trigger recovers without a relaunch or toggle flip.
    private func startFnPermissionWaiter() {
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard self.model.state.fnKeyTrigger, !self.fnMonitor.isRunning else {
                        self.fnPermissionWaiter?.invalidate()
                        self.fnPermissionWaiter = nil
                        return
                    }
                    if FnKeyMonitor.hasPermission {
                        self.applyFnTrigger(true)
                    }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fnPermissionWaiter = timer
    }

    // MARK: - Menu bar

    private func installMenuBar() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.toolTip = "Sokki"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggleItem = NSMenuItem(
            title: coordinator.isRecording ? "Stop && Insert" : "Start Dictation",
            action: #selector(toggleDictation),
            keyEquivalent: ""
        )
        toggleItem.target = self
        if let shortcut = KeyboardShortcut.parse(model.state.globalShortcut) {
            toggleItem.title += "   \(shortcut.compactDisplay)"
        }
        menu.addItem(toggleItem)

        if coordinator.isBusy {
            let cancelItem = NSMenuItem(title: "Cancel Dictation", action: #selector(cancelDictation), keyEquivalent: "")
            cancelItem.target = self
            menu.addItem(cancelItem)
        }

        if model.state.fnKeyTrigger && !fnMonitor.isRunning {
            let fixItem = NSMenuItem(
                title: "🌐 fn trigger is off — Grant Accessibility…",
                action: #selector(fixFnPermission),
                keyEquivalent: ""
            )
            fixItem.target = self
            fixItem.image = statusSymbol("exclamationmark.triangle.fill", color: .systemOrange)
            menu.addItem(fixItem)
        }

        menu.addItem(.separator())

        let modeMenu = NSMenu()
        for mode in DictationMode.allCases {
            let item = NSMenuItem(title: mode.rawValue, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = model.state.selectedMode == mode ? .on : .off
            if mode != .dictation && model.apiKeyState == .absent {
                item.title += " (API key required)"
            }
            modeMenu.addItem(item)
        }
        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let languageMenu = NSMenu()
        for option in DictationLanguage.options {
            let item = NSMenuItem(title: option.label, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.id
            item.state = model.state.localeIdentifier == option.id ? .on : .off
            languageMenu.addItem(item)
        }
        let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        menu.addItem(.separator())

        let records = ((try? model.history?.all()) ?? []).prefix(5)
        if records.isEmpty {
            let empty = NSMenuItem(title: "No dictations yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let recentMenu = NSMenu()
            for record in records {
                let preview = record.finalOutput
                    .replacingOccurrences(of: "\n", with: " ")
                    .prefix(48)
                let item = NSMenuItem(title: String(preview), action: #selector(copyRecent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = record.finalOutput
                item.toolTip = "Click to copy"
                recentMenu.addItem(item)
            }
            recentMenu.addItem(.separator())
            let openHistory = NSMenuItem(title: "Open History…", action: #selector(openHistoryTab), keyEquivalent: "")
            openHistory.target = self
            recentMenu.addItem(openHistory)
            let recentItem = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
            recentItem.submenu = recentMenu
            menu.addItem(recentItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let setupItem = NSMenuItem(title: "Setup Guide…", action: #selector(openOnboardingAction), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Sokki", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func updateStatusIcon(_ phase: RecordingCoordinator.Phase) {
        guard let button = statusItem?.button else { return }
        switch phase {
        case .idle:
            button.image = statusSymbol("mic", color: nil)
        case .recording:
            button.image = statusSymbol("record.circle.fill", color: .systemRed)
        case .transcribing:
            button.image = statusSymbol("waveform.circle.fill", color: .systemBlue)
        case .notice(let kind, _):
            switch kind {
            case .success:
                button.image = statusSymbol("checkmark.circle.fill", color: .systemGreen)
            case .info:
                button.image = statusSymbol("doc.on.clipboard.fill", color: .systemBlue)
            case .error:
                button.image = statusSymbol("exclamationmark.circle.fill", color: .systemOrange)
            }
        }
    }

    private func statusSymbol(_ name: String, color: NSColor?) -> NSImage? {
        guard var image = NSImage(systemSymbolName: name, accessibilityDescription: "Sokki") else {
            return nil
        }
        if let color {
            let configuration = NSImage.SymbolConfiguration(paletteColors: [color])
            image = image.withSymbolConfiguration(configuration) ?? image
            image.isTemplate = false
        } else {
            image.isTemplate = true
        }
        return image
    }

    // MARK: - Actions

    @objc private func toggleDictation() {
        coordinator.toggle()
    }

    @objc private func cancelDictation() {
        coordinator.cancel()
    }

    @objc private func fixFnPermission() {
        let reader = MacPermissionReader()
        reader.promptForAccessibility()
        reader.openAccessibilitySettings()
        // The waiter picks the grant up and starts the listener automatically.
        if fnPermissionWaiter == nil {
            startFnPermissionWaiter()
        }
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = DictationMode(rawValue: raw) else { return }
        model.state.selectedMode = mode
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        model.state.localeIdentifier = identifier
    }

    @objc private func copyRecent(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func openHistoryTab() {
        openSettings(tab: .history)
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    @objc private func openOnboardingAction() {
        openOnboarding()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Windows

    func openSettings(tab: SettingsTab = .general) {
        router.tab = tab
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.title = "Sokki Settings"
            window.contentView = NSHostingView(rootView: SettingsRootView(model: model, router: router))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.title = "Welcome to Sokki"
            // Keep the guide visible while system permission dialogs and
            // System Settings take focus away during setup.
            window.level = .floating
            window.delegate = self
            window.contentView = NSHostingView(rootView: SetupGuideView(model: model) { [weak self] in
                self?.onboardingWindow?.close()
            })
            window.center()
            onboardingWindow = window
        }
        model.refreshPermissions()
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the welcome window counts as finishing onboarding either
        // way; otherwise it would reopen on every launch.
        guard let window = notification.object as? NSWindow, window == onboardingWindow else { return }
        model.state.hasCompletedOnboarding = true
    }
}
