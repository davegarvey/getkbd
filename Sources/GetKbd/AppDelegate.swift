import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
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
        usbHubMonitor = USBHubMonitor(configuredHubIdentifiers: settings.selectedUSBHubIdentifiers)
        displayMonitor.primarySyncEnabled = settings.switchMainDisplay
        ownershipController = OwnershipController(
            keyboard: keyboardController
        )

        menuBarController = MenuBarController(
            ownership: ownershipController,
            settingsStore: settingsStore,
            showSettings: { [weak self] in self?.showSettings() },
            quit: { NSApp.terminate(nil) }
        )

        ownershipController.onChange = { [weak self] snapshot in
            self?.settingsWindowController?.update(snapshot: snapshot)
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
            guard let self else { return }
            self.displayMonitor.updatePrimaryHubSignal(
                configured: !self.settingsStore.value.selectedUSBHubs.isEmpty,
                present: isPresent
            )
            if isPresent {
                self.ownershipController.usbHubConnected()
            } else {
                self.ownershipController.usbHubDisconnected()
            }
        }
        usbHubMonitor.onDevicesChanged = { [weak self] in
            self?.settingsWindowController?.usbHubListChanged()
        }

        sleepMonitor.onWillSleep = { [weak self] in
            self?.displayMonitor.setPrimaryDisplaySleeping(true)
            self?.ownershipController.willSleep()
        }
        sleepMonitor.onDidWake = { [weak self] in
            guard let self else { return }
            self.displayMonitor.setPrimaryDisplaySleeping(true)
            self.usbHubMonitor.refresh()
            self.displayMonitor.updatePrimaryHubSignal(
                configured: !self.settingsStore.value.selectedUSBHubs.isEmpty,
                present: self.usbHubMonitor.isPresent
            )
            self.displayMonitor.setPrimaryDisplaySleeping(false)
            self.ownershipController.didWake(
                monitorPresent: self.displayMonitor.isPresent,
                usbHubPresent: self.usbHubMonitor.isPresent
            )
        }

        sleepMonitor.start()
        let monitorPresent = displayMonitor.start()
        usbHubMonitor.start()
        ownershipController.start(
            monitorPresent: monitorPresent,
            usbHubPresent: usbHubMonitor.isPresent
        )
        displayMonitor.updatePrimaryHubSignal(
            configured: !settings.selectedUSBHubs.isEmpty,
            present: usbHubMonitor.isPresent
        )
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
            display: displayMonitor,
            ownership: ownershipController,
            onChange: { [weak self] settings in
                self?.apply(settings)
            }
        )
        settingsWindowController = controller
        controller.showAndFocus()
    }

    private func apply(_ settings: AppSettings) {
        let previous = settingsStore.value
        settingsStore.replace(settings)

        if previous.selectedDisplay?.identifier != settings.selectedDisplay?.identifier {
            displayMonitor.configuredDisplayIdentifier = settings.selectedDisplay?.identifier
        }
        if previous.selectedUSBHubIdentifiers != settings.selectedUSBHubIdentifiers {
            usbHubMonitor.configuredHubIdentifiers = settings.selectedUSBHubIdentifiers
        }
        displayMonitor.primarySyncEnabled = settings.switchMainDisplay

        displayMonitor.updatePrimaryHubSignal(
            configured: !settings.selectedUSBHubs.isEmpty,
            present: usbHubMonitor.isPresent
        )

        ownershipController.updateSignals(
            monitorPresent: displayMonitor.isPresent,
            usbHubPresent: usbHubMonitor.isPresent
        )

        if previous.selectedKeyboard != settings.selectedKeyboard {
            ownershipController.reconfigureKeyboard(to: settings.selectedKeyboard)
        }

        menuBarController.refresh()
    }
}
