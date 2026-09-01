import AppKit
import Carbon
import Foundation

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let ownership: OwnershipController
    private let displayMonitor: DisplayMonitor
    private let settingsStore: SettingsStore
    private let peer: PeerVerificationController
    private let showSettings: () -> Void
    private let quit: () -> Void
    private var shortcutAvailable = true

    init(
        ownership: OwnershipController,
        displayMonitor: DisplayMonitor,
        settingsStore: SettingsStore,
        peer: PeerVerificationController,
        showSettings: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.ownership = ownership
        self.displayMonitor = displayMonitor
        self.settingsStore = settingsStore
        self.peer = peer
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
        let settings = settingsStore.value
        let snapshot = ownership.snapshot

        addLabel("getkbd", to: menu, bold: true)

        let keyboardName = settings.selectedKeyboard?.name ?? "Keyboard not configured"
        addLabel(keyboardName, to: menu, bold: true)
        addLabel(
            snapshot.keyboardState.menuTitle,
            to: menu,
            color: snapshot.keyboardState == .connectedLocal ? .systemGreen : .secondaryLabelColor
        )

        let setupStatus = Self.setupStatus(for: settings, peer: peer)
        let setupColor: NSColor = setupStatus == "Ready" ? .systemGreen : .systemOrange
        addLabel(
            setupStatus == "Ready" ? "Ready to switch" : setupStatus,
            to: menu,
            secondary: true,
            color: setupColor
        )

        addLabel("Switching: \(settings.automaticSource.menuTitle)", to: menu, secondary: true)

        let monitorStatus = displayMonitor.configuredDisplayIdentifier == nil
            ? "Display not configured"
            : (snapshot.monitorPresent ? "Display connected" : "Display disconnected")
        let hubStatus = settings.selectedUSBHub == nil
            ? "Input signal not configured"
            : (snapshot.usbHubPresent ? "Input signal connected" : "Input signal disconnected")
        switch settings.automaticSource {
        case .monitor:
            addLabel(monitorStatus, to: menu, secondary: true)
        case .usbHub:
            addLabel("\(monitorStatus) | \(hubStatus)", to: menu, secondary: true)
        case .off:
            break
        }

        if settings.automaticSource == .usbHub, peer.isPaired {
            addLabel(
                "Other Mac: \(peer.peerName ?? "Connected") | \(peer.verificationTitle)",
                to: menu,
                secondary: true
            )
        }

        if snapshot.displayHandoffState != .idle,
           snapshot.displayHandoffState != .restored {
            addLabel(snapshot.displayHandoffState.menuTitle, to: menu, secondary: true)
        }
        if let errorMessage = snapshot.errorMessage {
            addLabel(errorMessage, to: menu, secondary: true, color: .systemRed)
        }
        if let displayError = snapshot.displayHandoffError {
            addLabel(displayError, to: menu, secondary: true, color: .systemRed)
        }

        menu.addItem(.separator())

        if snapshot.displayHandoffState == .attentionRequired {
            let restoreItem = NSMenuItem(
                title: "Restore Display Layout",
                action: #selector(retryDisplayLayout),
                keyEquivalent: ""
            )
            restoreItem.target = self
            menu.addItem(restoreItem)
        }

        let shortcut = settings.shortcut
        let getItem = NSMenuItem(
            title: "Get Keyboard",
            action: #selector(getKeyboard),
            keyEquivalent: shortcut.keyEquivalent
        )
        getItem.target = self
        getItem.keyEquivalentModifierMask = Self.cocoaModifiers(for: shortcut)
        getItem.isEnabled = settings.selectedKeyboard != nil && !snapshot.isBusy

        let releaseItem = NSMenuItem(
            title: "Release Keyboard",
            action: #selector(releaseKeyboard),
            keyEquivalent: ""
        )
        releaseItem.target = self
        releaseItem.isEnabled = settings.selectedKeyboard != nil && !snapshot.isBusy

        if snapshot.keyboardState == .connectedLocal {
            menu.addItem(releaseItem)
            menu.addItem(getItem)
        } else {
            menu.addItem(getItem)
            menu.addItem(releaseItem)
        }

        if snapshot.keyboardState == .failed {
            let retryItem = NSMenuItem(
                title: ownership.desiredState == .disconnected ? "Retry Release" : "Retry Get Keyboard",
                action: #selector(retryKeyboard),
                keyEquivalent: ""
            )
            retryItem.target = self
            retryItem.isEnabled = settings.selectedKeyboard != nil
            menu.addItem(retryItem)
        }

        menu.addItem(.separator())

        let settingsTitle = setupStatus == "Ready" ? "Settings..." : "Finish Setup..."
        let settingsItem = NSMenuItem(title: settingsTitle, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)

        let shortcutTitle = shortcutAvailable
            ? "Shortcut: \(shortcut.displayString)"
            : "Shortcut: \(shortcut.displayString) (unavailable)"
        addLabel(shortcutTitle, to: menu, secondary: true)

        let quitItem = NSMenuItem(title: "Quit getkbd", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        return menu
    }

    private func addLabel(
        _ title: String,
        to menu: NSMenu,
        bold: Bool = false,
        secondary: Bool = false,
        color: NSColor? = nil
    ) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if bold {
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                    .foregroundColor: color ?? NSColor.labelColor
                ]
            )
        } else if secondary || color != nil {
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: secondary ? NSFont.smallSystemFontSize : NSFont.systemFontSize),
                    .foregroundColor: color ?? NSColor.secondaryLabelColor
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

        return NSImage(systemSymbolName: symbolName, accessibilityDescription: state.menuTitle)
    }

    private static func setupStatus(
        for settings: AppSettings,
        peer: PeerVerificationController
    ) -> String {
        guard settings.selectedKeyboard != nil else { return "Needs setup" }

        switch settings.automaticSource {
        case .monitor:
            return settings.selectedDisplay == nil ? "Needs setup" : "Ready"
        case .usbHub:
            guard settings.selectedDisplay != nil,
                  settings.selectedUSBHub != nil else { return "Needs setup" }
            return peer.verificationStatus == .verified && peer.kvmTestStatus == .passed
                ? "Ready"
                : "KVM test not verified"
        case .off:
            return "Ready"
        }
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

    @objc private func retryKeyboard() {
        if ownership.desiredState == .disconnected {
            ownership.manualRelease()
        } else {
            ownership.manualClaim()
        }
    }

    @objc private func retryDisplayLayout() {
        ownership.retryDisplayHandoff()
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func quitApplication() {
        quit()
    }
}
