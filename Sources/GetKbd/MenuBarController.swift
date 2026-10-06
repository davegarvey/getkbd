import AppKit
import Foundation

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let ownership: OwnershipController
    private let settingsStore: SettingsStore
    private let showSettings: () -> Void
    private let switchMonitor: (MonitorAction) -> Void
    private let enableBluetooth: () async -> Bool
    private var bluetoothActivation: BluetoothActivationState = .idle
    private let quit: () -> Void

    var monitorControlAvailable = false {
        didSet {
            guard monitorControlAvailable != oldValue else { return }
            refresh()
        }
    }

    init(
        ownership: OwnershipController,
        settingsStore: SettingsStore,
        showSettings: @escaping () -> Void,
        switchMonitor: @escaping (MonitorAction) -> Void,
        enableBluetooth: @escaping () async -> Bool,
        quit: @escaping () -> Void
    ) {
        self.ownership = ownership
        self.settingsStore = settingsStore
        self.showSettings = showSettings
        self.switchMonitor = switchMonitor
        self.enableBluetooth = enableBluetooth
        self.quit = quit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        refresh()
    }

    func refresh() {
        if ownership.snapshot.bluetoothAvailability == .poweredOn { bluetoothActivation = .idle }
        let status = currentStatus
        statusItem.button?.image = Self.statusImage(for: ownership.snapshot, title: status.title)
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = status.title
        statusItem.menu = makeMenu(for: status)
    }

    private var currentStatus: MenuStatus {
        MenuStatus.make(
            settings: settingsStore.value,
            snapshot: ownership.snapshot,
            desiredState: ownership.desiredState,
            monitorControlAvailable: monitorControlAvailable,
            bluetoothActivation: bluetoothActivation
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

        let keyboardAction = status.action == .finishSetup ? nil : status.action
        if keyboardAction != nil || status.monitorAction != nil {
            menu.addItem(.separator())
        }
        if let keyboardAction {
            menu.addItem(item(for: keyboardAction))
        }
        if let monitorAction = status.monitorAction {
            menu.addItem(item(for: monitorAction))
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
        case .tryNow:
            title = "Try Now"
            selector = #selector(tryKeyboardNow)
        case .enableBluetooth:
            title = "Turn Bluetooth On"
            selector = #selector(turnBluetoothOn)
        case .bluetoothSettings:
            title = "Open Bluetooth Settings…"
            selector = #selector(openBluetoothSettings)
        case .finishSetup:
            title = "Finish Setup…"
            selector = #selector(openSettings)
        }

        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func item(for action: MonitorAction) -> NSMenuItem {
        let title: String
        let selector: Selector
        switch action {
        case .switchToOtherMac:
            title = "Switch Monitor to Other Mac"
            selector = #selector(switchMonitorToOtherMac)
        case .switchToThisMac:
            title = "Switch Monitor to This Mac"
            selector = #selector(switchMonitorToThisMac)
        }

        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    static func statusImage(for snapshot: OwnershipSnapshot, title: String) -> NSImage? {
        let symbolName: String
        if snapshot.isBusy || snapshot.isRetryingClaim {
            // Distinct from the filled icon so that an attempt is not mistaken for a connection.
            symbolName = "keyboard.badge.ellipsis"
        } else {
            switch snapshot.keyboardState {
            case .failed:
                symbolName = "keyboard"
            case .disconnected, .unknown:
                symbolName = "keyboard"
            case .connecting, .disconnecting:
                symbolName = "keyboard.badge.ellipsis"
            case .connectedLocal:
                symbolName = "keyboard.fill"
            }
        }

        guard let keyboardImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) else {
            return nil
        }
        guard snapshot.bluetoothAvailability != .poweredOn || snapshot.keyboardState == .failed else {
            return keyboardImage
        }
        return warningImage(keyboard: keyboardImage, title: title)
    }

    /// macOS has no keyboard warning symbol. Draw a small badge with transparent
    /// clearance so the keyboard remains recognizable in either menu-bar theme.
    private static func warningImage(keyboard: NSImage, title: String) -> NSImage {
        let warning = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            keyboard.draw(in: NSRect(x: 0, y: 2, width: 18, height: 14))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: 12, y: -1, width: 11, height: 11)).fill()
            NSGraphicsContext.restoreGraphicsState()
            warning?.draw(in: NSRect(x: 13, y: 0, width: 9, height: 9))
            return true
        }
        image.accessibilityDescription = title
        image.isTemplate = true
        return image
    }

    @objc private func turnBluetoothOn() {
        guard bluetoothActivation != .enabling else { return }
        bluetoothActivation = .enabling
        refresh()
        Task { [weak self] in
            guard let self else { return }
            let succeeded = await self.enableBluetooth()
            self.bluetoothActivation = succeeded ? .idle : .failed
            self.refresh()
        }
    }

    @objc private func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }
        NSWorkspace.shared.open(url)
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

    @objc private func tryKeyboardNow() {
        ownership.connectNow()
    }

    @objc private func switchMonitorToOtherMac() {
        switchMonitor(.switchToOtherMac)
    }

    @objc private func switchMonitorToThisMac() {
        switchMonitor(.switchToThisMac)
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func quitApplication() {
        quit()
    }
}
