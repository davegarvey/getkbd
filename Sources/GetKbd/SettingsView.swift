import AppKit
import Carbon
import Combine
import Foundation
import SwiftUI

enum StatusTone {
    case positive
    case accent
    case warning
    case critical
    case neutral

    var color: Color {
        switch self {
        case .positive: return Color(nsColor: .systemGreen)
        case .accent: return Color(nsColor: .controlAccentColor)
        case .warning: return Color(nsColor: .systemOrange)
        case .critical: return Color(nsColor: .systemRed)
        case .neutral: return Color(nsColor: .secondaryLabelColor)
        }
    }

    var background: Color {
        color.opacity(0.12)
    }
}

struct SettingsReadiness {
    let title: String
    let detail: String
    let systemImage: String
    let tone: StatusTone
    let isReady: Bool
}

@MainActor
final class SettingsViewModel: ObservableObject {
    private let settingsStore: SettingsStore
    private let keyboard: KeyboardControlling
    private let usbHub: USBHubMonitor
    private let displayMonitor: DisplayMonitor
    private let ownership: OwnershipController
    private let onChange: (AppSettings) -> Void

    @Published private(set) var settings: AppSettings
    @Published private(set) var keyboardOptions: [KeyboardDescriptor] = []
    @Published private(set) var displayOptions: [DisplayDescriptor] = []
    @Published private(set) var hubOptions: [USBHubDescriptor] = []
    @Published private(set) var keyboardState: KeyboardConnectionState
    @Published private(set) var latestSnapshot: OwnershipSnapshot?
    @Published private(set) var isLoadingKeyboards = false
    @Published private(set) var message = ""
    @Published private(set) var loginStatus = ""
    @Published private(set) var isRecordingShortcut = false
    @Published private(set) var hubIdentificationMessage = ""
    @Published private(set) var isLocallyIdentifyingHub = false

    private var shortcutMonitor: Any?
    private var keyboardLoadTask: Task<Void, Never>?
    private var hubIdentificationBaseline: [String: USBHubDescriptor]?

    init(
        settingsStore: SettingsStore,
        keyboard: KeyboardControlling,
        usbHub: USBHubMonitor,
        display: DisplayMonitor,
        ownership: OwnershipController,
        onChange: @escaping (AppSettings) -> Void
    ) {
        self.settingsStore = settingsStore
        self.keyboard = keyboard
        self.usbHub = usbHub
        self.displayMonitor = display
        self.ownership = ownership
        self.onChange = onChange
        settings = settingsStore.value
        keyboardState = keyboard.state
        reload()
    }

    var readiness: SettingsReadiness {
        guard settings.selectedKeyboard != nil else {
            return SettingsReadiness(
                title: "Choose the shared keyboard",
                detail: "Select the Apple Magic Keyboard paired with both Macs.",
                systemImage: "keyboard",
                tone: .warning,
                isReady: false
            )
        }
        guard settings.selectedDisplay != nil else {
            return SettingsReadiness(
                title: "Choose the shared monitor",
                detail: "Select the monitor connected to this Mac.",
                systemImage: "rectangle.on.rectangle",
                tone: .warning,
                isReady: false
            )
        }
        guard settings.selectedUSBHub != nil else {
            return SettingsReadiness(
                title: "Identify the KVM input signal",
                detail: "Choose the USB hub that appears only when this Mac is selected by the monitor input.",
                systemImage: "cable.connector",
                tone: .warning,
                isReady: false
            )
        }
        return SettingsReadiness(
            title: "Ready to switch",
            detail: "Changing the monitor input moves the keyboard locally. No network connection is required.",
            systemImage: "checkmark.circle.fill",
            tone: .positive,
            isReady: true
        )
    }

    var isKeyboardConnected: Bool {
        keyboardState == .connectedLocal
    }

    var isBusy: Bool {
        latestSnapshot?.isBusy == true
    }

    var canClaimKeyboard: Bool {
        settings.selectedKeyboard != nil && !isBusy && !isKeyboardConnected
    }

    var canReleaseKeyboard: Bool {
        settings.selectedKeyboard != nil && !isBusy && isKeyboardConnected
    }

    var displayIsPresent: Bool {
        latestSnapshot?.monitorPresent ?? displayMonitor.isPresent
    }

    var hubIsPresent: Bool {
        latestSnapshot?.usbHubPresent ?? usbHub.isPresent
    }

    var displayStatusText: String {
        displayIsPresent ? "Connected" : "Not connected"
    }

    var displayTone: StatusTone {
        return displayIsPresent ? .positive : .warning
    }

    var hubStatusText: String {
        settings.selectedUSBHub == nil
            ? "Not configured"
            : (hubIsPresent ? "Connected" : "Not connected")
    }

    var hubTone: StatusTone {
        settings.selectedUSBHub == nil
            ? .neutral
            : (hubIsPresent ? .positive : .warning)
    }

    var hubDetectionTitle: String {
        isLocallyIdentifyingHub ? "Cancel detection" : "Identify input signal"
    }

    var hubDetectionDetail: String {
        if isLocallyIdentifyingHub {
            return "Listening. Change the monitor input, then wait for the hub list to change."
        }
        if let selectedHub = settings.selectedUSBHub {
            return "Selected signal: \(selectedHub.menuTitle)"
        }
        return "The selected hub must appear only on the active Mac."
    }

    func reload() {
        settings = settingsStore.value
        message = ""
        hubIdentificationMessage = ""
        hubIdentificationBaseline = nil
        isLocallyIdentifyingHub = false
        keyboardState = keyboard.state
        loginStatus = LoginItemController.statusDescription()
        reloadDisplayOptions(selected: settings.selectedDisplay)
        reloadHubOptions(selected: settings.selectedUSBHub)

        keyboardLoadTask?.cancel()
        isLoadingKeyboards = true
        keyboardOptions = settings.selectedKeyboard.map { [$0] } ?? []
        keyboardLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let devices = await self.keyboard.availableKeyboards()
            guard !Task.isCancelled else { return }
            self.keyboardOptions = self.mergedKeyboardOptions(devices, selected: self.settings.selectedKeyboard)
            self.isLoadingKeyboards = false
        }
    }

    func update(snapshot: OwnershipSnapshot) {
        latestSnapshot = snapshot
        keyboardState = snapshot.keyboardState
    }

    func showMessage(_ message: String) {
        self.message = message
    }

    func windowWillClose() {
        shortcutMonitor.map(NSEvent.removeMonitor)
        shortcutMonitor = nil
        keyboardLoadTask?.cancel()
        keyboardLoadTask = nil
        hubIdentificationBaseline = nil
        isLocallyIdentifyingHub = false
    }

    func usbHubListChanged() {
        reloadHubOptions(selected: settingsStore.value.selectedUSBHub)
        guard let baseline = hubIdentificationBaseline else { return }

        let current = Dictionary(
            usbHub.availableHubs.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let changedIdentifiers = Set(baseline.keys).symmetricDifference(current.keys)
        let candidates = changedIdentifiers.compactMap { current[$0] ?? baseline[$0] }
        guard candidates.count == 1,
              let descriptor = candidates.first else {
            guard changedIdentifiers.isEmpty else {
                hubIdentificationBaseline = nil
                isLocallyIdentifyingHub = false
                hubIdentificationMessage = "Several hubs changed. Choose the input signal manually."
                return
            }
            return
        }

        hubIdentificationBaseline = nil
        isLocallyIdentifyingHub = false
        var newSettings = settingsStore.value
        newSettings.selectedUSBHub = descriptor
        commit(newSettings)
        reloadHubOptions(selected: descriptor)
        hubIdentificationMessage = "Found \(descriptor.menuTitle)."
    }

    func selectKeyboard(identifier: String) {
        guard let descriptor = keyboardOptions.first(where: { $0.identifier == identifier }) else { return }
        var newSettings = settingsStore.value
        newSettings.selectedKeyboard = descriptor
        commit(newSettings)
        keyboardState = keyboard.state
    }

    func selectDisplay(identifier: String) {
        guard let descriptor = displayOptions.first(where: { $0.identifier == identifier }) else { return }
        var newSettings = settingsStore.value
        newSettings.selectedDisplay = descriptor
        commit(newSettings)
    }

    func selectHub(identifier: String) {
        guard let descriptor = hubOptions.first(where: { $0.identifier == identifier }) else { return }
        var newSettings = settingsStore.value
        newSettings.selectedUSBHub = descriptor
        commit(newSettings)
    }

    func setLaunchAtLogin(_ value: Bool) {
        guard LoginItemController.setEnabled(value) else {
            loginStatus = LoginItemController.statusDescription()
            message = "Unable to update login items. \(loginStatus)."
            return
        }

        var newSettings = settingsStore.value
        newSettings.launchAtLogin = value
        commit(newSettings)
        loginStatus = LoginItemController.statusDescription()
    }

    func identifyHub() {
        if isLocallyIdentifyingHub {
            hubIdentificationBaseline = nil
            isLocallyIdentifyingHub = false
            hubIdentificationMessage = ""
            return
        }

        hubIdentificationBaseline = Dictionary(
            usbHub.availableHubs.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        isLocallyIdentifyingHub = true
        hubIdentificationMessage = "Listening. Change the monitor input now."
    }

    func getKeyboard() {
        ownership.manualClaim()
    }

    func releaseKeyboard() {
        ownership.manualRelease()
    }

    func retryKeyboard() {
        if ownership.desiredState == .disconnected {
            ownership.manualRelease()
        } else {
            ownership.manualClaim()
        }
    }

    func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }
        NSWorkspace.shared.open(url)
    }

    func openDisplaySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func openLoginSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func toggleShortcutRecording() {
        if isRecordingShortcut {
            removeShortcutMonitor()
            return
        }

        isRecordingShortcut = true
        message = "Press at least one modifier and a key. Press Escape to cancel."
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
            message = ""
            return
        }

        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }

        guard modifiers != 0 else {
            message = "Add a modifier such as Command, Option, Control, or Shift."
            return
        }

        var newSettings = settingsStore.value
        newSettings.shortcut = ShortcutConfiguration(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers
        )
        removeShortcutMonitor()
        commit(newSettings)
        message = ""
    }

    private func removeShortcutMonitor() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
        isRecordingShortcut = false
    }

    private func commit(_ newSettings: AppSettings) {
        onChange(newSettings)
        settings = settingsStore.value
    }

    private func reloadDisplayOptions(selected: DisplayDescriptor?) {
        var displays = DisplayMonitor.currentDisplays().filter { !$0.isBuiltIn }
        if let selected,
           !displays.contains(where: { $0.identifier == selected.identifier }) {
            displays.insert(selected, at: 0)
        }
        displayOptions = displays
    }

    private func reloadHubOptions(selected: USBHubDescriptor?) {
        var hubs = usbHub.availableHubs
        if let selected,
           !hubs.contains(where: { $0.identifier == selected.identifier }) {
            hubs.insert(selected, at: 0)
        }
        hubOptions = hubs
    }

    private func mergedKeyboardOptions(
        _ devices: [KeyboardDescriptor],
        selected: KeyboardDescriptor?
    ) -> [KeyboardDescriptor] {
        var displayedDevices = devices
        if let selected,
           !displayedDevices.contains(where: { $0.identifier == selected.identifier }) {
            displayedDevices.insert(selected, at: 0)
        }
        return displayedDevices
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("getkbd")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("One Bluetooth keyboard for two Macs")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                ReadinessCard(readiness: viewModel.readiness)

                GroupBox("Shared devices") {
                    VStack(alignment: .leading, spacing: 14) {
                        DevicePickerRow(
                            title: "Keyboard",
                            detail: viewModel.settings.selectedKeyboard?.name ?? "Select the Apple Magic Keyboard paired with both Macs.",
                            systemImage: "keyboard.fill"
                        ) {
                            Picker("Keyboard", selection: Binding(
                                get: { viewModel.settings.selectedKeyboard?.identifier ?? "" },
                                set: { viewModel.selectKeyboard(identifier: $0) }
                            )) {
                                if viewModel.isLoadingKeyboards && viewModel.keyboardOptions.isEmpty {
                                    Text("Loading paired keyboards...").tag("")
                                } else if viewModel.keyboardOptions.isEmpty {
                                    Text("No paired keyboards found").tag("")
                                } else {
                                    Text("Select a keyboard").tag("")
                                    ForEach(viewModel.keyboardOptions) { keyboard in
                                        Text(keyboard.name).tag(keyboard.identifier)
                                    }
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        Divider()

                        DevicePickerRow(
                            title: "Monitor",
                            detail: viewModel.settings.selectedDisplay?.name ?? "Select the monitor connected to this Mac.",
                            systemImage: "rectangle.on.rectangle"
                        ) {
                            Picker("Monitor", selection: Binding(
                                get: { viewModel.settings.selectedDisplay?.identifier ?? "" },
                                set: { viewModel.selectDisplay(identifier: $0) }
                            )) {
                                if viewModel.displayOptions.isEmpty {
                                    Text("No external monitors found").tag("")
                                } else {
                                    Text("Select a monitor").tag("")
                                    ForEach(viewModel.displayOptions) { display in
                                        Text(display.name).tag(display.identifier)
                                    }
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        StatusRow(
                            title: "Monitor status",
                            value: viewModel.displayStatusText,
                            tone: viewModel.displayTone
                        )
                        Button("Open Display Settings") {
                            viewModel.openDisplaySettings()
                        }
                        .buttonStyle(.link)
                        Text("getkbd follows the USB hub signal: the monitor is primary when this Mac is active, and the built-in display becomes primary when it is active and the hub is absent. In clamshell mode, the monitor remains primary.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }

                GroupBox("Monitor input signal") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("The selected USB hub is the local active-input signal. It should appear only on the Mac selected by the monitor input.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        StatusRow(
                            title: "Hub status",
                            value: viewModel.hubStatusText,
                            tone: viewModel.hubTone
                        )

                        Picker("USB hub", selection: Binding(
                            get: { viewModel.settings.selectedUSBHub?.identifier ?? "" },
                            set: { viewModel.selectHub(identifier: $0) }
                        )) {
                            if viewModel.hubOptions.isEmpty {
                                Text("No USB hubs detected").tag("")
                            } else {
                                Text("Select a USB hub").tag("")
                                ForEach(viewModel.hubOptions) { hub in
                                    Text(hub.menuTitle).tag(hub.identifier)
                                }
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)

                        HStack(spacing: 10) {
                            Button(viewModel.hubDetectionTitle) {
                                viewModel.identifyHub()
                            }
                            .buttonStyle(.borderedProminent)
                            Text(viewModel.hubDetectionDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !viewModel.hubIdentificationMessage.isEmpty {
                            Text(viewModel.hubIdentificationMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("Manual controls and recovery") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Button("Get Keyboard") {
                                viewModel.getKeyboard()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!viewModel.canClaimKeyboard)

                            Button("Release Keyboard") {
                                viewModel.releaseKeyboard()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!viewModel.canReleaseKeyboard)

                            if viewModel.keyboardState == .failed {
                                Button("Try Again") {
                                    viewModel.retryKeyboard()
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        Text("getkbd always releases before sleep and re-evaluates the local hub and display after wake.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Image(systemName: "command")
                                .foregroundStyle(Color(nsColor: .controlAccentColor))
                            Text(viewModel.isRecordingShortcut ? "Press keys..." : viewModel.settings.shortcut.displayString)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button(viewModel.isRecordingShortcut ? "Cancel" : "Change Shortcut") {
                                viewModel.toggleShortcutRecording()
                            }
                            .buttonStyle(.bordered)
                        }

                        Toggle(
                            "Launch getkbd at login",
                            isOn: Binding(
                                get: { viewModel.settings.launchAtLogin },
                                set: { viewModel.setLaunchAtLogin($0) }
                            )
                        )
                        HStack(spacing: 8) {
                            Text("Login item: \(viewModel.loginStatus)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if viewModel.loginStatus == "Requires approval in System Settings" {
                                Button("Open Login Items") {
                                    viewModel.openLoginSettings()
                                }
                                .buttonStyle(.link)
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                if !viewModel.message.isEmpty {
                    Text(viewModel.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}

private struct ReadinessCard: View {
    let readiness: SettingsReadiness

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: readiness.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(readiness.tone.color)
                .frame(width: 34, height: 34)
                .background(readiness.tone.background)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(readiness.title)
                    .font(.headline)
                Text(readiness.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .background(readiness.tone.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DevicePickerRow<PickerContent: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    @ViewBuilder let picker: () -> PickerContent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .frame(width: 30, height: 30)
                .background(Color(nsColor: .controlAccentColor).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            picker()
                .frame(width: 250, alignment: .trailing)
        }
    }
}

private struct StatusRow: View {
    let title: String
    let value: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tone.color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
