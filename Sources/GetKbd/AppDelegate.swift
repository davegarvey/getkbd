import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let shortcutController = ShortcutController()
    private let sleepMonitor = SleepMonitor()

    private var keyboardController: IOBluetoothKeyboardController!
    private var displayMonitor: DisplayMonitor!
    private var usbHubMonitor: USBHubMonitor!
    private var ownershipController: OwnershipController!
    private var menuBarController: MenuBarController!
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settings = settingsStore.value
        keyboardController = IOBluetoothKeyboardController(configuredKeyboard: settings.selectedKeyboard)
        displayMonitor = DisplayMonitor(configuredDisplayIdentifier: settings.selectedDisplay?.identifier)
        usbHubMonitor = USBHubMonitor(configuredHubIdentifier: settings.selectedUSBHub?.identifier)
        ownershipController = OwnershipController(
            keyboard: keyboardController,
            behavior: AutomaticBehavior(
                claimOnMonitorConnect: settings.claimOnMonitorConnect,
                monitorTakesOwnershipFromManual: settings.monitorTakesOwnershipFromManual,
                releaseOnMonitorDisconnect: settings.releaseOnMonitorDisconnect,
                releaseBeforeSleep: settings.releaseBeforeSleep,
                automaticSource: settings.automaticSource
            )
        )

        menuBarController = MenuBarController(
            ownership: ownershipController,
            displayMonitor: displayMonitor,
            settingsStore: settingsStore,
            showSettings: { [weak self] in self?.showSettings() },
            quit: { NSApp.terminate(nil) }
        )

        ownershipController.onChange = { [weak self] _ in
            self?.menuBarController.refresh()
        }
        ownershipController.onKeyboardReconfigurationFailure = { [weak self] message in
            guard let self else { return }
            var restoredSettings = self.settingsStore.value
            restoredSettings.selectedKeyboard = self.keyboardController.configuredKeyboard
            self.settingsStore.replace(restoredSettings)
            self.settingsWindowController?.reload()
            self.settingsWindowController?.showMessage(message)
            self.menuBarController.refresh()
        }
        displayMonitor.onChange = { [weak self] isPresent in
            if isPresent {
                self?.ownershipController.monitorConnected()
            } else {
                self?.ownershipController.monitorDisconnected()
            }
        }
        usbHubMonitor.onChange = { [weak self] isPresent in
            if isPresent {
                self?.ownershipController.usbHubConnected()
            } else {
                self?.ownershipController.usbHubDisconnected()
            }
        }
        usbHubMonitor.onDevicesChanged = { [weak self] in
            self?.settingsWindowController?.usbHubListChanged()
        }

        sleepMonitor.onWillSleep = { [weak self] in
            self?.ownershipController.willSleep()
        }
        sleepMonitor.onDidWake = { [weak self] in
            guard let self else { return }
            self.ownershipController.didWake(monitorPresent: self.displayMonitor.isPresent)
        }

        shortcutController.onShortcut = { [weak self] in
            self?.ownershipController.manualClaim()
        }
        _ = shortcutController.register(settings.shortcut)

        sleepMonitor.start()
        let monitorPresent = displayMonitor.start()
        usbHubMonitor.start()
        ownershipController.start(
            monitorPresent: monitorPresent,
            usbHubPresent: usbHubMonitor.isPresent
        )
        menuBarController.setShortcutAvailable(shortcutController.isRegistered)

        if settings.launchAtLogin {
            _ = LoginItemController.setEnabled(true)
        }

        menuBarController.refresh()

        if settings.needsOnboarding {
            DispatchQueue.main.async { [weak self] in
                self?.showSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        sleepMonitor.stop()
        displayMonitor.stop()
        usbHubMonitor.stop()
        keyboardController.stop()
        shortcutController.unregister()
    }

    private func showSettings() {
        if let settingsWindowController {
            settingsWindowController.showAndFocus()
            return
        }

        let controller = SettingsWindowController(
            settingsStore: settingsStore,
            keyboard: keyboardController,
            usbHub: usbHubMonitor,
            onChange: { [weak self] settings in
                self?.apply(settings)
            }
        )
        settingsWindowController = controller
        controller.showAndFocus()
    }

    private func apply(_ settings: AppSettings) {
        let previous = settingsStore.value

        var effectiveSettings = settings
        var shortcutFailed = false
        if previous.shortcut != settings.shortcut,
           !shortcutController.register(settings.shortcut) {
            effectiveSettings.shortcut = previous.shortcut
            shortcutFailed = true
        }

        settingsStore.replace(effectiveSettings)

        if previous.selectedDisplay?.identifier != effectiveSettings.selectedDisplay?.identifier {
            displayMonitor.configuredDisplayIdentifier = effectiveSettings.selectedDisplay?.identifier
        }
        if previous.selectedUSBHub?.identifier != effectiveSettings.selectedUSBHub?.identifier {
            usbHubMonitor.configuredHubIdentifier = effectiveSettings.selectedUSBHub?.identifier
        }

        ownershipController.updateBehavior(
            AutomaticBehavior(
                claimOnMonitorConnect: effectiveSettings.claimOnMonitorConnect,
                monitorTakesOwnershipFromManual: effectiveSettings.monitorTakesOwnershipFromManual,
                releaseOnMonitorDisconnect: effectiveSettings.releaseOnMonitorDisconnect,
                releaseBeforeSleep: effectiveSettings.releaseBeforeSleep,
                automaticSource: effectiveSettings.automaticSource
            ),
            monitorPresent: displayMonitor.isPresent,
            usbHubPresent: usbHubMonitor.isPresent
        )

        if previous.selectedKeyboard != effectiveSettings.selectedKeyboard {
            ownershipController.reconfigureKeyboard(
                to: effectiveSettings.selectedKeyboard,
                monitorPresent: displayMonitor.isPresent
            )
        }

        if effectiveSettings.shortcut != settings.shortcut {
            settingsWindowController?.reload()
        }
        if shortcutFailed {
            settingsWindowController?.showMessage("That shortcut could not be registered.")
        }
        menuBarController.setShortcutAvailable(shortcutController.isRegistered)
        menuBarController.refresh()
    }
}
