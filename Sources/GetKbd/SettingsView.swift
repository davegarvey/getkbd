import AppKit
import Combine
import Foundation
import SwiftUI

enum SetupStep: Equatable {
    case keyboard
    case monitor
    case monitorSwitching
    case complete
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
    @Published private(set) var latestSnapshot: OwnershipSnapshot?
    @Published private(set) var isLoadingKeyboards = false
    @Published private(set) var message = ""
    @Published private(set) var loginNeedsApproval = false
    @Published private(set) var identification: HubIdentification?
    @Published private(set) var identificationFailed = false
    @Published private(set) var completedSetupThisSession = false

    private var keyboardLoadTask: Task<Void, Never>?
    private var identificationTask: Task<Void, Never>?

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
        reload()
    }

    var setupStep: SetupStep {
        if settings.selectedKeyboard == nil { return .keyboard }
        if settings.selectedDisplay == nil { return .monitor }
        if settings.selectedUSBHubs.isEmpty { return .monitorSwitching }
        return .complete
    }

    var isIdentifying: Bool {
        identification.map { !$0.isFinished } ?? false
    }

    var identificationStatus: String {
        if identificationFailed {
            return "The switch wasn’t detected. Switch to your other Mac and back again."
        }
        switch identification?.phase {
        case .waitingForFirstSwitch:
            return "Waiting for the monitor to switch to your other Mac…"
        case .waitingForSwitchBack:
            return "Now switch the monitor back to this Mac…"
        case .succeeded, .timedOut, nil:
            return ""
        }
    }

    var monitorNote: String? {
        guard let selected = settings.selectedDisplay else { return nil }
        let online = DisplayMonitor.currentDisplays().contains { $0.identifier == selected.identifier }
        return online ? nil : "Not connected"
    }

    func reload() {
        settings = settingsStore.value
        message = ""
        loginNeedsApproval = LoginItemController.needsApproval
        reloadDisplayOptions()

        keyboardLoadTask?.cancel()
        isLoadingKeyboards = true
        keyboardOptions = settings.selectedKeyboard.map { [$0] } ?? []
        keyboardLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let devices = await self.keyboard.availableKeyboards()
            guard !Task.isCancelled else { return }
            self.keyboardOptions = Self.merged(devices, selected: self.settings.selectedKeyboard)
            self.isLoadingKeyboards = false
            if self.settings.selectedKeyboard == nil, devices.count == 1 {
                self.selectKeyboard(identifier: devices[0].identifier)
            }
        }
    }

    func update(snapshot: OwnershipSnapshot) {
        latestSnapshot = snapshot
    }

    func showMessage(_ message: String) {
        self.message = message
    }

    func windowWillClose() {
        keyboardLoadTask?.cancel()
        keyboardLoadTask = nil
        cancelIdentification()
        completedSetupThisSession = false
    }

    func usbHubListChanged() {
        guard var identification, !identification.isFinished else { return }
        identification.observe(usbHub.availableHubs, at: Date())
        self.identification = identification
    }

    func selectKeyboard(identifier: String) {
        guard let descriptor = keyboardOptions.first(where: { $0.identifier == identifier }) else { return }
        var newSettings = settingsStore.value
        newSettings.selectedKeyboard = descriptor
        commit(newSettings)
    }

    func selectDisplay(identifier: String) {
        guard let descriptor = displayOptions.first(where: { $0.identifier == identifier }) else { return }
        var newSettings = settingsStore.value
        newSettings.selectedDisplay = descriptor
        commit(newSettings)
    }

    func setSwitchMainDisplay(_ value: Bool) {
        var newSettings = settingsStore.value
        newSettings.switchMainDisplay = value
        commit(newSettings)
    }

    func setLaunchAtLogin(_ value: Bool) {
        guard LoginItemController.setEnabled(value) else {
            loginNeedsApproval = LoginItemController.needsApproval
            message = "macOS didn’t update the login item. Check Login Items in System Settings."
            return
        }

        var newSettings = settingsStore.value
        newSettings.launchAtLogin = value
        commit(newSettings)
        loginNeedsApproval = LoginItemController.needsApproval
    }

    func startIdentification() {
        cancelIdentification()
        identificationFailed = false
        identification = HubIdentification(hubs: usbHub.availableHubs, at: Date())
        identificationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled, let self else { return }
                self.tickIdentification()
                guard self.isIdentifying else { return }
            }
        }
    }

    func cancelIdentification() {
        identificationTask?.cancel()
        identificationTask = nil
        identification = nil
    }

    func openLoginSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func tickIdentification() {
        guard var identification else { return }
        let now = Date()
        identification.observe(usbHub.availableHubs, at: now)
        identification.tick(at: now)
        self.identification = identification

        switch identification.phase {
        case .succeeded(let hubs):
            identificationTask = nil
            self.identification = nil
            let wasIncomplete = settingsStore.value.needsOnboarding
            var newSettings = settingsStore.value
            newSettings.selectedUSBHubs = hubs
            commit(newSettings)
            if wasIncomplete, !settings.needsOnboarding {
                completedSetupThisSession = true
            }
        case .timedOut:
            identificationTask = nil
            self.identification = nil
            identificationFailed = true
        case .waitingForFirstSwitch, .waitingForSwitchBack:
            break
        }
    }

    private func commit(_ newSettings: AppSettings) {
        onChange(newSettings)
        settings = settingsStore.value
    }

    private func reloadDisplayOptions() {
        var displays = DisplayMonitor.currentDisplays()
        if settings.selectedDisplay == nil, displays.count == 1 {
            displayOptions = displays
            selectDisplay(identifier: displays[0].identifier)
            return
        }
        if let selected = settings.selectedDisplay,
           !displays.contains(where: { $0.identifier == selected.identifier }) {
            displays.insert(selected, at: 0)
        }
        displayOptions = displays
    }

    private static func merged(
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
        Form {
            if viewModel.setupStep != .complete || viewModel.completedSetupThisSession {
                Section {
                    SetupSection(viewModel: viewModel)
                }
            }

            Section {
                Picker(selection: Binding(
                    get: { viewModel.settings.selectedKeyboard?.identifier ?? "" },
                    set: { viewModel.selectKeyboard(identifier: $0) }
                )) {
                    if viewModel.settings.selectedKeyboard == nil {
                        Text(viewModel.isLoadingKeyboards ? "Looking for keyboards…" : "Choose…").tag("")
                    }
                    ForEach(viewModel.keyboardOptions) { keyboard in
                        Text(keyboard.name).tag(keyboard.identifier)
                    }
                } label: {
                    Text("Keyboard")
                }

                Picker(selection: Binding(
                    get: { viewModel.settings.selectedDisplay?.identifier ?? "" },
                    set: { viewModel.selectDisplay(identifier: $0) }
                )) {
                    if viewModel.settings.selectedDisplay == nil {
                        Text(viewModel.displayOptions.isEmpty ? "No monitor connected" : "Choose…").tag("")
                    }
                    ForEach(viewModel.displayOptions) { display in
                        Text(display.name).tag(display.identifier)
                    }
                } label: {
                    RowLabel(title: "Monitor", note: viewModel.monitorNote)
                }

                if viewModel.setupStep == .complete {
                    MonitorSwitchingRow(viewModel: viewModel)
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { viewModel.settings.switchMainDisplay },
                    set: { viewModel.setSwitchMainDisplay($0) }
                )) {
                    Text("Switch the main display with the monitor")
                    Text("When the monitor switches to your other Mac, the menu bar and windows move to the built-in display.")
                }

                Toggle(isOn: Binding(
                    get: { viewModel.settings.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                )) {
                    Text("Open at login")
                    if viewModel.loginNeedsApproval {
                        Text("Needs approval in System Settings.")
                    }
                }
                if viewModel.loginNeedsApproval {
                    Button("Open Login Items…") {
                        viewModel.openLoginSettings()
                    }
                }
            }

            if !viewModel.message.isEmpty {
                Section {
                    Text(viewModel.message)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SetupSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch viewModel.setupStep {
            case .keyboard:
                Text("Choose your keyboard")
                    .font(.headline)
                Text("Pick the keyboard you share between your Macs. It must be paired with both.")
                    .foregroundStyle(.secondary)
            case .monitor:
                Text("Choose your monitor")
                    .font(.headline)
                Text("Pick the monitor both Macs are connected to.")
                    .foregroundStyle(.secondary)
            case .monitorSwitching:
                Text("Teach getkbd your monitor")
                    .font(.headline)
                Text("Switch your monitor to your other Mac, then switch it back.")
                    .foregroundStyle(.secondary)
                IdentificationControls(viewModel: viewModel)
            case .complete:
                Label("You’re all set", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("Switching the monitor now moves the keyboard. Set up getkbd on your other Mac too.")
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
    }
}

private struct IdentificationControls: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        HStack(spacing: 10) {
            if viewModel.isIdentifying {
                ProgressView()
                    .controlSize(.small)
                Text(viewModel.identificationStatus)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    viewModel.cancelIdentification()
                }
            } else {
                Button(viewModel.identificationFailed ? "Try Again" : "Start") {
                    viewModel.startIdentification()
                }
                .buttonStyle(.borderedProminent)
                if viewModel.identificationFailed {
                    Text(viewModel.identificationStatus)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.top, 4)
    }
}

private struct MonitorSwitchingRow: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        if viewModel.isIdentifying || viewModel.identificationFailed {
            VStack(alignment: .leading, spacing: 6) {
                Text("Monitor switching")
                Text("Switch your monitor to your other Mac, then switch it back.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                IdentificationControls(viewModel: viewModel)
            }
        } else {
            LabeledContent("Monitor switching") {
                HStack(spacing: 8) {
                    Label("Set up", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                    Button("Set Up Again…") {
                        viewModel.startIdentification()
                    }
                }
            }
        }
    }
}

private struct RowLabel: View {
    let title: String
    let note: String?

    var body: some View {
        Text(title)
        if let note {
            Text(note)
                .foregroundStyle(.orange)
        }
    }
}
