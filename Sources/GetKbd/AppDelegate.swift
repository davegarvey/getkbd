import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let sleepMonitor = SleepMonitor()
    private let monitorInputControl: MonitorInputControl = IOAVMonitorInputControl()
    private lazy var monitorInputLearner = MonitorInputLearner(control: monitorInputControl)
    private var monitorSwitchWatchdog: Task<Void, Never>?

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
            switchMonitor: { [weak self] action in self?.switchMonitor(action) },
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
                self?.learnMonitorInput()
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
            self.monitorSwitchWatchdog?.cancel()
            self.monitorSwitchWatchdog = nil
            self.learnMonitorInput()
        }
        monitorInputLearner.onReading = { [weak self] value, isThisMac, displayIdentifier in
            self?.recordMonitorInput(value, isThisMac: isThisMac, displayIdentifier: displayIdentifier)
        }
        monitorInputLearner.onAvailabilityChange = { [weak self] available in
            self?.menuBarController.monitorControlAvailable = available
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
            self.learnMonitorInput()
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
        learnMonitorInput()

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
        monitorInputLearner.cancel()
    }

    /// Reads the monitor's input for the current hub state so that the menu can offer
    /// monitor switching. Learning never affects keyboard ownership.
    private func learnMonitorInput() {
        let settings = settingsStore.value
        guard !settings.needsOnboarding,
              let displayIdentifier = settings.selectedDisplay?.identifier,
              displayMonitor.isPresent else {
            monitorInputLearner.cancel()
            return
        }
        monitorInputLearner.learn(displayIdentifier: displayIdentifier, hubPresent: usbHubMonitor.isPresent)
    }

    private func recordMonitorInput(_ value: Int, isThisMac: Bool, displayIdentifier: String) {
        var settings = settingsStore.value
        guard settings.selectedDisplay?.identifier == displayIdentifier else { return }
        guard let inputs = LearnedMonitorInputs.recording(
            value,
            forThisMac: isThisMac,
            displayIdentifier: displayIdentifier,
            into: settings.monitorInputs
        ) else {
            GetKbdLog.event("monitor.input.conflict", "\(isThisMac ? "thisMac" : "otherMac")=\(value)")
            return
        }
        guard inputs != settings.monitorInputs else { return }

        settings.monitorInputs = inputs
        settingsStore.replace(settings)
        GetKbdLog.event("monitor.input.learned", "\(isThisMac ? "thisMac" : "otherMac")=\(value)")
        menuBarController.refresh()
    }

    private func switchMonitor(_ action: MonitorAction) {
        let settings = settingsStore.value
        guard let displayIdentifier = settings.selectedDisplay?.identifier,
              let inputs = settings.currentMonitorInputs,
              let target = action == .switchToOtherMac ? inputs.otherMac : inputs.thisMac else {
            return
        }

        let control = monitorInputControl
        GetKbdLog.event("monitor.switch.requested", "input=\(target)")
        monitorSwitchWatchdog?.cancel()
        monitorSwitchWatchdog = Task { [weak self] in
            let sent = await control.setInput(target, displayIdentifier: displayIdentifier)
            guard sent else {
                GetKbdLog.error("monitor.switch.failed", "The input change could not be sent")
                self?.monitorSwitchWatchdog = nil
                return
            }
            // A hub-group transition cancels this task; reaching the end means the monitor ignored the command.
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            GetKbdLog.error("monitor.switch.failed", "The hub group did not change within 15 seconds")
            self?.monitorSwitchWatchdog = nil
        }
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
        var settings = settings
        if previous.selectedDisplay?.identifier != settings.selectedDisplay?.identifier {
            settings.monitorInputs = nil
        }
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

        if previous.selectedDisplay?.identifier != settings.selectedDisplay?.identifier ||
            previous.selectedUSBHubIdentifiers != settings.selectedUSBHubIdentifiers {
            learnMonitorInput()
        }
        menuBarController.refresh()
    }
}
