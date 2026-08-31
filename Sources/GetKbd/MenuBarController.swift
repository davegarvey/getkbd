import AppKit
import Carbon
import Foundation

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let ownership: OwnershipController
    private let displayMonitor: DisplayMonitor
    private let settingsStore: SettingsStore
    private let showSettings: () -> Void
    private let quit: () -> Void
    private var shortcutAvailable = true

    init(
        ownership: OwnershipController,
        displayMonitor: DisplayMonitor,
        settingsStore: SettingsStore,
        showSettings: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.ownership = ownership
        self.displayMonitor = displayMonitor
        self.settingsStore = settingsStore
        self.showSettings = showSettings
        self.quit = quit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.image = Self.statusImage(for: ownership.snapshot.keyboardState)
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = "getkbd"
        refresh()
    }

    func refresh() {
        statusItem.button?.image = Self.statusImage(for: ownership.snapshot.keyboardState)
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = tooltip
        statusItem.menu = makeMenu()
    }

    func setShortcutAvailable(_ available: Bool) {
        shortcutAvailable = available
        refresh()
    }

    private var tooltip: String {
        let keyboardName = settingsStore.value.selectedKeyboard?.name ?? "Keyboard not configured"
        return "\(keyboardName): \(ownership.snapshot.keyboardState.menuTitle)"
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        addLabel("getkbd", to: menu, bold: true)

        let keyboardName = settingsStore.value.selectedKeyboard?.name ?? "Keyboard not configured"
        addLabel("Keyboard: \(keyboardName)", to: menu)
        addLabel(ownership.snapshot.keyboardState.menuTitle, to: menu)
        addLabel("Ownership: \(ownership.snapshot.ownershipReason.menuTitle)", to: menu, secondary: true)

        let monitorTitle = displayMonitor.configuredDisplayIdentifier == nil
            ? "Desk monitor: Not configured"
            : "Desk monitor: \(ownership.snapshot.monitorPresent ? "Connected" : "Disconnected")"
        addLabel(monitorTitle, to: menu)

        menu.addItem(.separator())

        let shortcut = settingsStore.value.shortcut
        let getItem = NSMenuItem(
            title: "Get Keyboard",
            action: #selector(getKeyboard),
            keyEquivalent: shortcut.keyEquivalent
        )
        getItem.target = self
        getItem.keyEquivalentModifierMask = Self.cocoaModifiers(for: shortcut)
        getItem.isEnabled = settingsStore.value.selectedKeyboard != nil && !ownership.snapshot.isBusy
        menu.addItem(getItem)

        let releaseItem = NSMenuItem(
            title: "Release Keyboard",
            action: #selector(releaseKeyboard),
            keyEquivalent: ""
        )
        releaseItem.target = self
        releaseItem.isEnabled = settingsStore.value.selectedKeyboard != nil && !ownership.snapshot.isBusy
        menu.addItem(releaseItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)

        let shortcutTitle = shortcutAvailable
            ? "Get Keyboard shortcut: \(shortcut.displayString)"
            : "Get Keyboard shortcut: \(shortcut.displayString) (unavailable)"
        addLabel(shortcutTitle, to: menu, secondary: true)

        let quitItem = NSMenuItem(title: "Quit getkbd", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        return menu
    }

    private func addLabel(_ title: String, to menu: NSMenu, bold: Bool = false, secondary: Bool = false) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if bold {
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
            )
        } else if secondary {
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
        }
        menu.addItem(item)
    }

    private static func statusImage(for state: KeyboardConnectionState) -> NSImage? {
        let symbolName: String
        switch state {
        case .failed:
            symbolName = "exclamationmark.triangle"
        case .disconnected, .unknown:
            symbolName = "keyboard"
        case .connecting, .disconnecting, .connectedLocal:
            symbolName = "keyboard.fill"
        }

        return NSImage(systemSymbolName: symbolName, accessibilityDescription: "Keyboard")
    }

    private static func cocoaModifiers(for shortcut: ShortcutConfiguration) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if shortcut.modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if shortcut.modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if shortcut.modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if shortcut.modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    @objc private func getKeyboard() {
        ownership.manualClaim()
    }

    @objc private func releaseKeyboard() {
        ownership.manualRelease()
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func quitApplication() {
        quit()
    }
}
