import AppKit
import Carbon
import Foundation

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settingsStore: SettingsStore
    private let keyboard: KeyboardControlling
    private let onChange: (AppSettings) -> Void

    private let keyboardPopup = NSPopUpButton()
    private let displayPopup = NSPopUpButton()
    private let keyboardStateLabel = NSTextField(labelWithString: "")
    private let autoClaimCheckbox = NSButton(checkboxWithTitle: "Get keyboard when monitor connects", target: nil, action: nil)
    private let monitorOwnershipCheckbox = NSButton(
        checkboxWithTitle: "Let the monitor take ownership after a manual claim",
        target: nil,
        action: nil
    )
    private let autoReleaseCheckbox = NSButton(checkboxWithTitle: "Release keyboard when monitor disconnects", target: nil, action: nil)
    private let sleepCheckbox = NSButton(checkboxWithTitle: "Release keyboard before sleep", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch getkbd at login", target: nil, action: nil)
    private let shortcutButton = NSButton(title: "", target: nil, action: nil)
    private let messageLabel = NSTextField(labelWithString: "")

    private var shortcutMonitor: Any?

    init(
        settingsStore: SettingsStore,
        keyboard: KeyboardControlling,
        onChange: @escaping (AppSettings) -> Void
    ) {
        self.settingsStore = settingsStore
        self.keyboard = keyboard
        self.onChange = onChange

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "getkbd Settings"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        buildView()
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAndFocus() {
        reload()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func reload() {
        let settings = settingsStore.value
        reloadKeyboardPopup(selected: settings.selectedKeyboard)
        reloadDisplayPopup(selected: settings.selectedDisplay)

        keyboardStateLabel.stringValue = keyboard.state.menuTitle
        autoClaimCheckbox.state = settings.claimOnMonitorConnect ? .on : .off
        monitorOwnershipCheckbox.state = settings.monitorTakesOwnershipFromManual ? .on : .off
        autoReleaseCheckbox.state = settings.releaseOnMonitorDisconnect ? .on : .off
        sleepCheckbox.state = settings.releaseBeforeSleep ? .on : .off
        loginCheckbox.state = settings.launchAtLogin ? .on : .off
        shortcutButton.title = settings.shortcut.displayString
        messageLabel.stringValue = ""
    }

    func showMessage(_ message: String) {
        messageLabel.stringValue = message
    }

    func windowWillClose(_ notification: Notification) {
        removeShortcutMonitor()
    }

    private func buildView() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        contentView.addSubview(scrollView)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        stack.addArrangedSubview(sectionTitle("Keyboard"))
        stack.addArrangedSubview(fieldLabel("Paired keyboard"))
        keyboardPopup.target = self
        keyboardPopup.action = #selector(keyboardChanged)
        keyboardPopup.widthAnchor.constraint(equalToConstant: 390).isActive = true
        stack.addArrangedSubview(keyboardPopup)
        keyboardStateLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(keyboardStateLabel)

        stack.addArrangedSubview(sectionTitle("Desk Monitor"))
        stack.addArrangedSubview(fieldLabel("External display used to claim the keyboard"))
        displayPopup.target = self
        displayPopup.action = #selector(displayChanged)
        displayPopup.widthAnchor.constraint(equalToConstant: 390).isActive = true
        stack.addArrangedSubview(displayPopup)

        let refreshButton = NSButton(
            title: "Refresh Keyboard and Monitor Lists",
            target: self,
            action: #selector(refreshSelectors)
        )
        refreshButton.bezelStyle = .rounded
        stack.addArrangedSubview(refreshButton)

        stack.addArrangedSubview(sectionTitle("Automatic Behaviour"))
        autoClaimCheckbox.target = self
        autoClaimCheckbox.action = #selector(behaviorChanged)
        monitorOwnershipCheckbox.target = self
        monitorOwnershipCheckbox.action = #selector(behaviorChanged)
        autoReleaseCheckbox.target = self
        autoReleaseCheckbox.action = #selector(behaviorChanged)
        sleepCheckbox.target = self
        sleepCheckbox.action = #selector(behaviorChanged)
        stack.addArrangedSubview(autoClaimCheckbox)
        stack.addArrangedSubview(monitorOwnershipCheckbox)
        stack.addArrangedSubview(autoReleaseCheckbox)
        stack.addArrangedSubview(sleepCheckbox)

        stack.addArrangedSubview(sectionTitle("Shortcut"))
        shortcutButton.target = self
        shortcutButton.action = #selector(recordShortcut)
        shortcutButton.bezelStyle = .rounded
        shortcutButton.widthAnchor.constraint(equalToConstant: 220).isActive = true
        stack.addArrangedSubview(shortcutButton)

        stack.addArrangedSubview(sectionTitle("Startup"))
        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginChanged)
        stack.addArrangedSubview(loginCheckbox)

        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(messageLabel)
    }

    private func reloadKeyboardPopup(selected: KeyboardDescriptor?) {
        keyboardPopup.removeAllItems()
        let devices = keyboard.availableKeyboards()

        if devices.isEmpty {
            keyboardPopup.addItem(withTitle: "No paired Bluetooth keyboards found")
            keyboardPopup.item(at: 0)?.isEnabled = false
            return
        }

        devices.forEach { device in
            keyboardPopup.addItem(withTitle: device.name)
            keyboardPopup.lastItem?.representedObject = device
        }

        if let selected,
           let index = devices.firstIndex(where: { $0.identifier == selected.identifier }) {
            keyboardPopup.selectItem(at: index)
        } else {
            keyboardPopup.select(nil)
        }
    }

    private func reloadDisplayPopup(selected: DisplayDescriptor?) {
        displayPopup.removeAllItems()
        let currentDisplays = DisplayMonitor.currentDisplays()
        var displays = currentDisplays.filter { !$0.isBuiltIn }

        if let selected,
           !selected.isBuiltIn,
           !displays.contains(where: { $0.identifier == selected.identifier }) {
            displays.insert(selected, at: 0)
        }

        if displays.isEmpty {
            displayPopup.addItem(withTitle: "No external displays currently connected")
            displayPopup.item(at: 0)?.isEnabled = false
            return
        }

        displays.forEach { display in
            let isPresent = currentDisplays.contains { $0.identifier == display.identifier }
            let title = isPresent ? display.name : "\(display.name) (not currently connected)"
            displayPopup.addItem(withTitle: title)
            displayPopup.lastItem?.representedObject = display
        }

        if let selected,
           let index = displays.firstIndex(where: { $0.identifier == selected.identifier }) {
            displayPopup.selectItem(at: index)
        } else {
            displayPopup.select(nil)
        }
    }

    private func sectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func fieldLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.textColor = .secondaryLabelColor
        return label
    }

    @objc private func keyboardChanged() {
        guard let descriptor = keyboardPopup.selectedItem?.representedObject as? KeyboardDescriptor else { return }
        var settings = settingsStore.value
        settings.selectedKeyboard = descriptor
        commit(settings)
        keyboardStateLabel.stringValue = keyboard.state.menuTitle
    }

    @objc private func displayChanged() {
        guard let descriptor = displayPopup.selectedItem?.representedObject as? DisplayDescriptor else { return }
        var settings = settingsStore.value
        settings.selectedDisplay = descriptor
        commit(settings)
    }

    @objc private func refreshSelectors() {
        reload()
    }

    @objc private func behaviorChanged() {
        var settings = settingsStore.value
        settings.claimOnMonitorConnect = autoClaimCheckbox.state == .on
        settings.monitorTakesOwnershipFromManual = monitorOwnershipCheckbox.state == .on
        settings.releaseOnMonitorDisconnect = autoReleaseCheckbox.state == .on
        settings.releaseBeforeSleep = sleepCheckbox.state == .on
        commit(settings)
    }

    @objc private func loginChanged() {
        let enabled = loginCheckbox.state == .on
        guard LoginItemController.setEnabled(enabled) else {
            loginCheckbox.state = enabled ? .off : .on
            messageLabel.stringValue = "Unable to update login item. Use the packaged app bundle."
            return
        }

        var settings = settingsStore.value
        settings.launchAtLogin = enabled
        commit(settings)
    }

    @objc private func recordShortcut() {
        if shortcutMonitor != nil {
            removeShortcutMonitor()
            shortcutButton.title = settingsStore.value.shortcut.displayString
            return
        }

        shortcutButton.title = "Press keys..."
        messageLabel.stringValue = "Press at least one modifier and a key."
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.captureShortcut(event)
            }
            return nil
        }
    }

    private func captureShortcut(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            removeShortcutMonitor()
            shortcutButton.title = settingsStore.value.shortcut.displayString
            messageLabel.stringValue = ""
            return
        }

        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }

        guard modifiers != 0 else { return }

        var settings = settingsStore.value
        settings.shortcut = ShortcutConfiguration(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        removeShortcutMonitor()
        commit(settings)

        if settingsStore.value.shortcut == settings.shortcut {
            shortcutButton.title = settings.shortcut.displayString
            messageLabel.stringValue = ""
        }
    }

    private func removeShortcutMonitor() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
    }

    private func commit(_ settings: AppSettings) {
        onChange(settings)
    }
}
