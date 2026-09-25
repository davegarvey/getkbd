import AppKit
import Foundation

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let ownership: OwnershipController
    private let settingsStore: SettingsStore
    private let showSettings: () -> Void
    private let quit: () -> Void

    init(
        ownership: OwnershipController,
        settingsStore: SettingsStore,
        showSettings: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.ownership = ownership
        self.settingsStore = settingsStore
        self.showSettings = showSettings
        self.quit = quit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        refresh()
    }

    func refresh() {
        let status = currentStatus
        statusItem.button?.image = Self.statusImage(for: ownership.snapshot.keyboardState, title: status.title)
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = status.title
        statusItem.menu = makeMenu(for: status)
    }

    private var currentStatus: MenuStatus {
        MenuStatus.make(
            settings: settingsStore.value,
            snapshot: ownership.snapshot,
            desiredState: ownership.desiredState
        )
    }

    private func makeMenu(for status: MenuStatus) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let stateItem = NSMenuItem(title: status.title, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        stateItem.attributedTitle = NSAttributedString(
            string: status.title,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.labelColor
            ]
        )
        menu.addItem(stateItem)

        if let action = status.action, action != .finishSetup {
            menu.addItem(.separator())
            menu.addItem(item(for: action))
        }

        menu.addItem(.separator())

        let settingsTitle = status.action == .finishSetup ? "Finish Setup…" : "Settings…"
        let settingsItem = NSMenuItem(title: settingsTitle, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit getkbd", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func item(for action: MenuAction) -> NSMenuItem {
        let title: String
        let selector: Selector
        switch action {
        case .release:
            title = "Release Keyboard"
            selector = #selector(releaseKeyboard)
        case .get:
            title = "Get Keyboard"
            selector = #selector(getKeyboard)
        case .retry:
            title = "Try Again"
            selector = #selector(retryKeyboard)
        case .finishSetup:
            title = "Finish Setup…"
            selector = #selector(openSettings)
        }

        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private static func statusImage(for state: KeyboardConnectionState, title: String) -> NSImage? {
        let symbolName: String
        switch state {
        case .failed:
            symbolName = "exclamationmark.triangle"
        case .disconnected, .unknown:
            symbolName = "keyboard"
        case .connecting, .disconnecting, .connectedLocal:
            symbolName = "keyboard.fill"
        }

        return NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
    }

    @objc private func getKeyboard() {
        ownership.manualClaim()
    }

    @objc private func releaseKeyboard() {
        ownership.manualRelease()
    }

    @objc private func retryKeyboard() {
        if ownership.desiredState == .disconnected {
            ownership.manualRelease()
        } else {
            ownership.manualClaim()
        }
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func quitApplication() {
        quit()
    }
}
