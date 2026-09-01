import AppKit
import Carbon
import Combine
import Foundation
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case overview
    case setup
    case behavior
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .setup: return "Desk setup"
        case .behavior: return "Behavior"
        case .advanced: return "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "rectangle.grid.2x2"
        case .setup: return "wand.and.stars"
        case .behavior: return "slider.horizontal.3"
        case .advanced: return "gearshape.2"
        }
    }
}

enum SettingsReadinessAction {
    case setup
    case retryDisplayLayout
}

struct SettingsReadiness {
    let title: String
    let detail: String
    let systemImage: String
    let tone: StatusTone
    let actionTitle: String
    let action: SettingsReadinessAction
    let isReady: Bool
}

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

@MainActor
final class SettingsViewModel: ObservableObject {
    private let settingsStore: SettingsStore
    private let keyboard: KeyboardControlling
    private let usbHub: USBHubMonitor
    private let displayMonitor: DisplayMonitor
    private let ownership: OwnershipController
    private let peer: PeerVerificationController
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

    @Published private(set) var peerConnectionState: PeerConnectionState = .unavailable
    @Published private(set) var peerVerificationStatus: PeerVerificationStatus = .unverified
    @Published private(set) var peerTestStatus: KVMTestStatus = .notStarted
    @Published private(set) var peerName: String?
    @Published private(set) var peerStatusText = ""
    @Published private(set) var peerVerificationText = ""
    @Published private(set) var peerMessage = ""
    @Published private(set) var pairingCode: String?
    @Published private(set) var discoveredPeers: [String] = []
    @Published var selectedPeerIndex = 0

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
        peer: PeerVerificationController,
        onChange: @escaping (AppSettings) -> Void
    ) {
        self.settingsStore = settingsStore
        self.keyboard = keyboard
        self.usbHub = usbHub
        self.displayMonitor = display
        self.ownership = ownership
        self.peer = peer
        self.onChange = onChange
        settings = settingsStore.value
        keyboardState = keyboard.state
        reload()
    }

    var readiness: SettingsReadiness {
        let settings = settings

        guard settings.selectedKeyboard != nil else {
            return SettingsReadiness(
                title: "Choose your keyboard",
                detail: "Select the shared Bluetooth keyboard to start using getkbd.",
                systemImage: "keyboard",
                tone: .warning,
                actionTitle: "Continue setup",
                action: .setup,
                isReady: false
            )
        }

        if let snapshot = latestSnapshot,
           snapshot.displayHandoffState == .attentionRequired,
           let error = snapshot.displayHandoffError {
            return SettingsReadiness(
                title: "Display layout needs attention",
                detail: error,
                systemImage: "exclamationmark.triangle.fill",
                tone: .critical,
                actionTitle: "Retry layout",
                action: .retryDisplayLayout,
                isReady: false
            )
        }

        switch settings.automaticSource {
        case .monitor:
            guard settings.selectedDisplay != nil else {
                return SettingsReadiness(
                    title: "Choose your shared display",
                    detail: "Select the external display you move between the two Macs.",
                    systemImage: "rectangle.on.rectangle",
                    tone: .warning,
                    actionTitle: "Continue setup",
                    action: .setup,
                    isReady: false
                )
            }

            return SettingsReadiness(
                title: "Ready to switch",
                detail: "getkbd watches the display connection and moves the keyboard with it.",
                systemImage: "checkmark.circle.fill",
                tone: .positive,
                actionTitle: "Review setup",
                action: .setup,
                isReady: true
            )
        case .usbHub:
            guard settings.selectedDisplay != nil else {
                return SettingsReadiness(
                    title: "Choose your shared display",
                    detail: "Select the display whose input you change between Macs.",
                    systemImage: "rectangle.on.rectangle",
                    tone: .warning,
                    actionTitle: "Continue setup",
                    action: .setup,
                    isReady: false
                )
            }
            guard settings.selectedUSBHub != nil else {
                return SettingsReadiness(
                    title: "Find the input signal",
                    detail: "Detect the USB connection that follows the monitor input.",
                    systemImage: "cable.connector",
                    tone: .warning,
                    actionTitle: "Continue setup",
                    action: .setup,
                    isReady: false
                )
            }
            guard peer.isPaired else {
                return SettingsReadiness(
                    title: "Connect the other Mac",
                    detail: "Pair the other getkbd instance before relying on automatic input switching.",
                    systemImage: "person.2",
                    tone: .warning,
                    actionTitle: "Continue setup",
                    action: .setup,
                    isReady: false
                )
            }
            if peerVerificationStatus == .unsafe {
                return SettingsReadiness(
                    title: "Input signal needs attention",
                    detail: "Both Macs can see the USB connection, so automatic switching is unsafe.",
                    systemImage: "exclamationmark.triangle.fill",
                    tone: .critical,
                    actionTitle: "Review setup",
                    action: .setup,
                    isReady: false
                )
            }
            guard peerVerificationStatus == .verified else {
                return SettingsReadiness(
                    title: "Verify the input signal",
                    detail: peer.verificationTitle,
                    systemImage: "arrow.left.arrow.right",
                    tone: .accent,
                    actionTitle: "Continue setup",
                    action: .setup,
                    isReady: false
                )
            }
            guard peerTestStatus == .passed else {
                return SettingsReadiness(
                    title: "Test the handoff",
                    detail: peer.kvmTestTitle,
                    systemImage: "arrow.triangle.2.circlepath",
                    tone: .accent,
                    actionTitle: "Continue setup",
                    action: .setup,
                    isReady: false
                )
            }

            return SettingsReadiness(
                title: "Ready to switch",
                detail: "Changing the monitor input will move the keyboard and protect your display layout.",
                systemImage: "checkmark.circle.fill",
                tone: .positive,
                actionTitle: "Review setup",
                action: .setup,
                isReady: true
            )
        case .off:
            return SettingsReadiness(
                title: "Ready for manual switching",
                detail: "Use the menu bar or your keyboard shortcut whenever you want to move the keyboard.",
                systemImage: "hand.tap",
                tone: .neutral,
                actionTitle: "Review setup",
                action: .setup,
                isReady: true
            )
        }
    }

    var needsConfiguration: Bool {
        settings.needsOnboarding
    }

    var isKeyboardConnected: Bool {
        keyboardState == .connectedLocal
    }

    var isPeerPaired: Bool {
        peer.isPaired
    }

    var isPeerConnected: Bool {
        peer.isPeerConnected
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
        let connection = displayIsPresent ? "Connected" : "Not connected"
        guard let state = latestSnapshot?.displayHandoffState,
              state != .idle,
              state != .restored else {
            return connection
        }
        return "\(connection) | \(state.menuTitle)"
    }

    var displayTone: StatusTone {
        latestSnapshot?.displayHandoffState == .attentionRequired
            ? .critical
            : (displayIsPresent ? .positive : .warning)
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

    var peerConnectionTone: StatusTone {
        switch peerConnectionState {
        case .paired:
            return .positive
        case .discovered, .connecting, .awaitingConfirmation:
            return .accent
        case .stale:
            return .warning
        case .unavailable:
            return .neutral
        }
    }

    var peerConnectionIcon: String {
        switch peerConnectionState {
        case .paired: return "checkmark.circle.fill"
        case .discovered: return "magnifyingglass"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .awaitingConfirmation: return "checkmark.shield"
        case .stale, .unavailable: return "person.2"
        }
    }

    var peerVerificationTone: StatusTone {
        switch peerVerificationStatus {
        case .verified: return .positive
        case .unsafe: return .critical
        case .listening: return .accent
        case .ambiguous, .noSignal: return .warning
        case .unverified, .unavailable: return .neutral
        }
    }

    var peerActionTitle: String {
        if peer.isPaired { return "Forget this Mac" }
        switch peerConnectionState {
        case .connecting:
            return "Connecting..."
        case .awaitingConfirmation:
            return "Pairing in progress"
        case .paired, .stale:
            return "Forget this Mac"
        case .discovered, .unavailable:
            break
        }
        if discoveredPeers.count == 1, let discoveredPeerName = peer.discoveredPeerName {
            return "Connect to \(discoveredPeerName)"
        }
        if peer.hasDiscoveredPeer { return "Connect to selected Mac" }
        return "Find other Mac"
    }

    var peerActionEnabled: Bool {
        guard peerConnectionState != .connecting,
              peerConnectionState != .awaitingConfirmation else {
            return false
        }
        return peer.isPaired || peer.hasDiscoveredPeer
    }

    var peerConnectionDetail: String {
        if peer.isPaired {
            return "Paired and sharing setup status."
        }
        switch peerConnectionState {
        case .discovered:
            return "Select this Mac below to start pairing."
        case .connecting:
            return "Waiting for the other Mac to respond."
        case .awaitingConfirmation:
            return "Compare the pairing code on both Macs."
        default:
            return "Open getkbd on the other Mac and keep both Macs on the same network."
        }
    }

    var peerSafetyText: String {
        if peerVerificationStatus == .unsafe {
            return "Both Macs can see this USB connection. Automatic switching is unsafe."
        }
        return "The selected connection should appear on one Mac at a time."
    }

    var hubDetectionTitle: String {
        if peer.isPeerConnected, peerVerificationStatus == .listening {
            return "Finish detection"
        }
        if isLocallyIdentifyingHub {
            return "Cancel detection"
        }
        return "Detect input signal"
    }

    var hubDetectionDetail: String {
        if peer.isPeerConnected, peerVerificationStatus == .listening {
            return "Listening. Change the monitor input to the other Mac."
        }
        if isLocallyIdentifyingHub {
            return "Listening. Switch the monitor input or reconnect the display cable."
        }
        if let selectedHub = settings.selectedUSBHub {
            return "Selected signal: \(selectedHub.menuTitle)"
        }
        return "Identify the USB connection that follows the monitor input."
    }

    var kvmTestTone: StatusTone {
        switch peerTestStatus {
        case .passed: return .positive
        case .waitingForFirstSwitch, .waitingForReturn: return .accent
        case .failed: return .critical
        case .skipped: return .warning
        case .notStarted: return .neutral
        }
    }

    var kvmTestDetail: String {
        switch peerTestStatus {
        case .notStarted:
            return "Run a round trip to confirm that both Macs release and claim the keyboard correctly."
        case .waitingForFirstSwitch:
            return "Change the monitor input to the other Mac."
        case .waitingForReturn:
            return "Switch the monitor input back to finish the test."
        case .passed:
            return "Both directions completed successfully."
        case .skipped:
            return "The handoff is configured but has not been verified."
        case .failed:
            return peer.lastMessage ?? "The handoff test failed. Try again."
        }
    }

    var shortcutTitle: String {
        isRecordingShortcut ? "Press keys..." : settings.shortcut.displayString
    }

    var loginTone: StatusTone {
        loginStatus == "Enabled" ? .positive : .warning
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
        reloadAutomaticState()
        refreshPeerState()

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

    func refreshPeerState() {
        peerConnectionState = peer.connectionState
        peerVerificationStatus = peer.verificationStatus
        peerTestStatus = peer.kvmTestStatus
        peerName = peer.peerName
        peerStatusText = peer.peerDetail
        peerVerificationText = peer.verificationTitle
        peerMessage = peer.lastMessage ?? ""
        pairingCode = peer.pairingCode
        discoveredPeers = peer.discoveredPeerSummaries
        applyDetectedHubIfNeeded()
        if discoveredPeers.isEmpty {
            selectedPeerIndex = 0
        } else {
            selectedPeerIndex = min(selectedPeerIndex, discoveredPeers.count - 1)
        }
    }

    func showMessage(_ message: String) {
        self.message = message
    }

    func windowWillClose() {
        removeShortcutMonitor()
        keyboardLoadTask?.cancel()
        keyboardLoadTask = nil
        hubIdentificationBaseline = nil
        isLocallyIdentifyingHub = false
    }

    func usbHubListChanged() {
        reloadHubOptions(selected: settingsStore.value.selectedUSBHub)

        applyDetectedHubIfNeeded()

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
        var settings = settingsStore.value
        settings.selectedUSBHub = descriptor
        commit(settings)
        reloadHubOptions(selected: descriptor)
        hubIdentificationMessage = "Found \(descriptor.menuTitle)."
    }

    func selectKeyboard(identifier: String) {
        guard let descriptor = keyboardOptions.first(where: { $0.identifier == identifier }) else { return }
        var settings = settingsStore.value
        settings.selectedKeyboard = descriptor
        commit(settings)
        keyboardState = keyboard.state
    }

    func selectDisplay(identifier: String) {
        guard let descriptor = displayOptions.first(where: { $0.identifier == identifier }) else { return }
        var settings = settingsStore.value
        settings.selectedDisplay = descriptor
        commit(settings)
    }

    func selectHub(identifier: String) {
        guard let descriptor = hubOptions.first(where: { $0.identifier == identifier }) else { return }
        var settings = settingsStore.value
        settings.selectedUSBHub = descriptor
        commit(settings)
    }

    func selectAutomaticSource(_ source: AutomaticSource) {
        var settings = settingsStore.value
        settings.automaticSource = source
        commit(settings)
        refreshPeerState()
    }

    func setClaimOnMonitorConnect(_ value: Bool) {
        var settings = settingsStore.value
        settings.claimOnMonitorConnect = value
        commit(settings)
    }

    func setMonitorOwnership(_ value: Bool) {
        var settings = settingsStore.value
        settings.monitorTakesOwnershipFromManual = value
        commit(settings)
    }

    func setReleaseOnMonitorDisconnect(_ value: Bool) {
        var settings = settingsStore.value
        settings.releaseOnMonitorDisconnect = value
        commit(settings)
    }

    func setReleaseBeforeSleep(_ value: Bool) {
        var settings = settingsStore.value
        settings.releaseBeforeSleep = value
        commit(settings)
    }

    func setLaunchAtLogin(_ value: Bool) {
        guard LoginItemController.setEnabled(value) else {
            loginStatus = LoginItemController.statusDescription()
            message = "Unable to update login items. \(loginStatus)."
            return
        }

        var settings = settingsStore.value
        settings.launchAtLogin = value
        commit(settings)
        loginStatus = LoginItemController.statusDescription()
    }

    func refreshDevices() {
        reload()
    }

    func identifyHub() {
        if peer.isPeerConnected {
            if peerVerificationStatus == .listening {
                peer.finishHubDetection()
                hubIdentificationMessage = "No complementary input change was detected."
            } else {
                peer.beginHubDetection(localHubs: usbHub.availableHubs)
                hubIdentificationMessage = "Listening. Change the monitor input to the other Mac."
            }
            refreshPeerState()
            return
        }

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
        hubIdentificationMessage = "Listening. Switch the monitor input or reconnect the display cable."
    }

    func connectToPeer() {
        if peer.isPaired {
            peer.forgetPeer()
        } else {
            peer.connectToDiscoveredPeer(at: selectedPeerIndex)
        }
        refreshPeerState()
    }

    func confirmPairing() {
        peer.confirmPairing()
        refreshPeerState()
    }

    func testSwitching() {
        peer.startKVMTest()
        refreshPeerState()
    }

    func skipSwitchingTest() {
        peer.skipKVMTest()
        refreshPeerState()
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

    func retryDisplayLayout() {
        ownership.retryDisplayHandoff()
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

        var settings = settingsStore.value
        settings.shortcut = ShortcutConfiguration(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        removeShortcutMonitor()
        commit(settings)
        message = ""
    }

    private func removeShortcutMonitor() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
        isRecordingShortcut = false
    }

    private func commit(_ settings: AppSettings) {
        onChange(settings)
        self.settings = settingsStore.value
        loginStatus = LoginItemController.statusDescription()
    }

    private func reloadAutomaticState() {
        settings = settingsStore.value
    }

    private func reloadDisplayOptions(selected: DisplayDescriptor?) {
        let currentDisplays = DisplayMonitor.currentDisplays()
        var displays = currentDisplays.filter { !$0.isBuiltIn }

        if let selected,
           !selected.isBuiltIn,
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

    private func applyDetectedHubIfNeeded() {
        guard peerVerificationStatus == .verified,
              let descriptor = peer.detectedHub,
              settingsStore.value.selectedUSBHub?.identifier != descriptor.identifier else {
            return
        }

        var settings = settingsStore.value
        settings.selectedUSBHub = descriptor
        commit(settings)
        reloadHubOptions(selected: descriptor)
        hubIdentificationMessage = "Found the input signal: \(descriptor.menuTitle)."
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var selection: SettingsPage?

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        _selection = State(initialValue: viewModel.needsConfiguration ? .setup : .overview)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel, selection: $selection)
        } detail: {
            detailView(for: selection ?? .overview)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Color(nsColor: .controlAccentColor))
        .frame(minWidth: 820, minHeight: 580)
    }

    @ViewBuilder
    private func detailView(for page: SettingsPage) -> some View {
        switch page {
        case .overview:
            OverviewPage(viewModel: viewModel, openSetup: { selection = .setup })
        case .setup:
            SetupPage(viewModel: viewModel)
        case .behavior:
            BehaviorPage(viewModel: viewModel, openSetup: { selection = .setup })
        case .advanced:
            AdvancedPage(viewModel: viewModel)
        }
    }
}

private struct SidebarView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var selection: SettingsPage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .controlAccentColor))
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Color(nsColor: .controlAccentColor).opacity(0.13))
                        )
                    Text("getkbd")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                Text("Keyboard for your shared desk")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 16)

            List(selection: $selection) {
                Section("Workspace") {
                    ForEach([SettingsPage.overview, .setup]) { page in
                        Label(page.title, systemImage: page.systemImage)
                            .tag(page as SettingsPage?)
                    }
                }

                Section("Preferences") {
                    ForEach([SettingsPage.behavior, .advanced]) { page in
                        Label(page.title, systemImage: page.systemImage)
                            .tag(page as SettingsPage?)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: viewModel.readiness.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(viewModel.readiness.tone.color)
                    .frame(width: 24, height: 24)
                    .background(viewModel.readiness.tone.background)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.readiness.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                    Text(viewModel.readiness.isReady ? "All systems ready" : "Setup needs your attention")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 190, idealWidth: 210, maxWidth: 240)
    }
}

private struct OverviewPage: View {
    @ObservedObject var viewModel: SettingsViewModel
    let openSetup: () -> Void

    var body: some View {
        PageScroll {
            PageHeader(
                eyebrow: "Overview",
                title: "Your desk at a glance",
                subtitle: "See who owns the keyboard, check the shared hardware, and switch Macs when you need to."
            )

            ReadinessCard(readiness: viewModel.readiness) {
                switch viewModel.readiness.action {
                case .setup:
                    openSetup()
                case .retryDisplayLayout:
                    viewModel.retryDisplayLayout()
                }
            }

            Panel {
                PanelHeader(
                    title: "Quick actions",
                    subtitle: "Move the keyboard manually when you need to override automation."
                )

                HStack(spacing: 12) {
                    if viewModel.isKeyboardConnected {
                        Button {
                            viewModel.releaseKeyboard()
                        } label: {
                            Label("Release keyboard", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canReleaseKeyboard)
                    } else {
                        Button {
                            viewModel.getKeyboard()
                        } label: {
                            Label("Get keyboard", systemImage: "keyboard.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canClaimKeyboard)
                    }

                    if viewModel.keyboardState == .failed {
                        Button {
                            viewModel.retryKeyboard()
                        } label: {
                            Label("Try again", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Text("These actions are also available from the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Live status")
                    .font(.title3.weight(.semibold))

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    StatusTile(
                        title: "Keyboard",
                        value: viewModel.keyboardState.menuTitle,
                        detail: viewModel.settings.selectedKeyboard?.name ?? "No keyboard selected",
                        systemImage: "keyboard.fill",
                        tone: viewModel.isKeyboardConnected ? .positive : .warning
                    )
                    StatusTile(
                        title: "Shared display",
                        value: viewModel.displayStatusText,
                        detail: viewModel.settings.selectedDisplay?.name ?? "No display selected",
                        systemImage: "rectangle.on.rectangle",
                        tone: viewModel.displayTone
                    )
                    StatusTile(
                        title: "Input signal",
                        value: viewModel.hubStatusText,
                        detail: viewModel.settings.selectedUSBHub?.name ?? "Only used for monitor-input switching",
                        systemImage: "cable.connector",
                        tone: viewModel.hubTone
                    )
                    StatusTile(
                        title: "Other Mac",
                        value: viewModel.settings.automaticSource == .usbHub
                            ? viewModel.peerStatusText
                            : "Not needed",
                        detail: viewModel.settings.automaticSource == .usbHub
                            ? viewModel.peerVerificationText
                            : "This setup works locally",
                        systemImage: "person.2",
                        tone: viewModel.settings.automaticSource == .usbHub
                            ? viewModel.peerConnectionTone
                            : .neutral
                    )
                }
            }

            if !viewModel.message.isEmpty {
                InlineNotice(text: viewModel.message, tone: .warning)
            }
        }
    }
}

private struct SetupPage: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        PageScroll {
            PageHeader(
                eyebrow: "Desk setup",
                title: "Tell getkbd how you switch",
                subtitle: "Choose the physical action you take at the desk. getkbd will only show the pieces needed for that setup."
            )

            Panel {
                PanelHeader(
                    title: "How do you switch between Macs?",
                    subtitle: "You can change this later without re-pairing the keyboard."
                )

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach([AutomaticSource.monitor, .usbHub, .off], id: \.self) { source in
                        SourceChoice(
                            source: source,
                            isSelected: viewModel.settings.automaticSource == source
                        ) {
                            viewModel.selectAutomaticSource(source)
                        }
                    }
                }
            }

            Panel {
                PanelHeader(
                    title: "Shared hardware",
                    subtitle: "Select the devices that belong to this desk."
                )

                KeyboardDeviceRow(viewModel: viewModel)

                if viewModel.settings.automaticSource != .off {
                    Divider()
                    DisplayDeviceRow(viewModel: viewModel)
                }
            }

            if viewModel.settings.automaticSource == .usbHub {
                PeerPanel(viewModel: viewModel)
                HubPanel(viewModel: viewModel)
                TestPanel(viewModel: viewModel)
            } else if viewModel.settings.automaticSource == .monitor {
                Panel {
                    PanelHeader(
                        title: "What happens next",
                        subtitle: "When the selected display appears, getkbd can claim the keyboard. When it disappears, getkbd can release it."
                    )
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Color(nsColor: .controlAccentColor))
                        Text("The two Macs do not need to communicate for display-cable switching. Repeat this setup on the other Mac.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Panel {
                    PanelHeader(
                        title: "Manual mode",
                        subtitle: "getkbd will not react to display or USB changes. Use the menu bar or shortcut to move the keyboard."
                    )
                    Label("No automatic switching is enabled", systemImage: "hand.tap")
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.message.isEmpty {
                InlineNotice(text: viewModel.message, tone: .warning)
            }
        }
    }
}

private struct BehaviorPage: View {
    @ObservedObject var viewModel: SettingsViewModel
    let openSetup: () -> Void

    var body: some View {
        PageScroll {
            PageHeader(
                eyebrow: "Behavior",
                title: "Make switching feel automatic",
                subtitle: "Choose how much getkbd should do for you. Changes apply immediately."
            )

            Panel {
                PanelHeader(
                    title: "Current switching method",
                    subtitle: "The physical desk action is configured in Desk setup."
                )
                HStack(spacing: 12) {
                    Image(systemName: viewModel.settings.automaticSource.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .controlAccentColor))
                        .frame(width: 38, height: 38)
                        .background(Color(nsColor: .controlAccentColor).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.settings.automaticSource.uiTitle)
                            .font(.headline)
                        Text(viewModel.settings.automaticSource.uiDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change") {
                        openSetup()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if viewModel.settings.automaticSource == .monitor {
                Panel {
                    PanelHeader(
                        title: "Display connection",
                        subtitle: "These rules apply when the selected display is connected or disconnected."
                    )
                    Toggle(
                        "Get the keyboard when the display connects",
                        isOn: Binding(
                            get: { viewModel.settings.claimOnMonitorConnect },
                            set: { viewModel.setClaimOnMonitorConnect($0) }
                        )
                    )
                    Toggle(
                        "Let the display take ownership after a manual claim",
                        isOn: Binding(
                            get: { viewModel.settings.monitorTakesOwnershipFromManual },
                            set: { viewModel.setMonitorOwnership($0) }
                        )
                    )
                    .disabled(!viewModel.settings.claimOnMonitorConnect)
                    Toggle(
                        "Release the keyboard when the display disconnects",
                        isOn: Binding(
                            get: { viewModel.settings.releaseOnMonitorDisconnect },
                            set: { viewModel.setReleaseOnMonitorDisconnect($0) }
                        )
                    )
                }
            }

            Panel {
                PanelHeader(
                    title: "Sleep safety",
                    subtitle: "Release the keyboard before this Mac sleeps so the other Mac can use it."
                )
                Toggle(
                    "Release the keyboard before sleep",
                    isOn: Binding(
                        get: { viewModel.settings.releaseBeforeSleep },
                        set: { viewModel.setReleaseBeforeSleep($0) }
                    )
                )
            }

            Panel {
                PanelHeader(
                    title: "Keyboard shortcut",
                    subtitle: "Use a global shortcut to claim the keyboard in any app."
                )
                HStack(spacing: 12) {
                    Image(systemName: "command")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .controlAccentColor))
                        .frame(width: 38, height: 38)
                        .background(Color(nsColor: .controlAccentColor).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.shortcutTitle)
                            .font(.system(.headline, design: .monospaced))
                        Text(viewModel.isRecordingShortcut ? "Listening for a new shortcut" : "Press the button to record a new shortcut")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(viewModel.isRecordingShortcut ? "Cancel" : "Change shortcut") {
                        viewModel.toggleShortcutRecording()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Panel {
                PanelHeader(
                    title: "Startup",
                    subtitle: "Keep getkbd available when you sign in."
                )
                Toggle(
                    "Launch getkbd at login",
                    isOn: Binding(
                        get: { viewModel.settings.launchAtLogin },
                        set: { viewModel.setLaunchAtLogin($0) }
                    )
                )
                HStack(spacing: 8) {
                    StatusPill(text: viewModel.loginStatus, tone: viewModel.loginTone)
                    if viewModel.loginStatus == "Requires approval in System Settings" {
                        Button("Open Login Items") {
                            viewModel.openLoginSettings()
                        }
                        .buttonStyle(.link)
                    }
                }
            }

            if !viewModel.message.isEmpty {
                InlineNotice(text: viewModel.message, tone: .warning)
            }
        }
    }
}

private struct AdvancedPage: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        PageScroll {
            PageHeader(
                eyebrow: "Advanced",
                title: "Diagnostics and recovery",
                subtitle: "Technical details and system links are kept here so the normal setup stays focused."
            )

            Panel {
                PanelHeader(
                    title: "Detected devices",
                    subtitle: "Refresh these lists if a paired device or USB hub is missing."
                )
                DetailRow(
                    title: "Keyboard",
                    value: viewModel.settings.selectedKeyboard?.name ?? "Not selected",
                    detail: viewModel.settings.selectedKeyboard?.identifier
                )
                Divider()
                DetailRow(
                    title: "Display",
                    value: viewModel.settings.selectedDisplay?.name ?? "Not selected",
                    detail: viewModel.settings.selectedDisplay?.identifier
                )
                Divider()
                DetailRow(
                    title: "Input signal",
                    value: viewModel.settings.selectedUSBHub?.menuTitle ?? "Not selected",
                    detail: viewModel.settings.selectedUSBHub?.identifier
                )
                Button {
                    viewModel.refreshDevices()
                } label: {
                    Label("Refresh device lists", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            Panel {
                PanelHeader(
                    title: "Display layout recovery",
                    subtitle: "getkbd temporarily protects the shared display during a keyboard release."
                )
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: viewModel.displayTone == .critical ? "exclamationmark.triangle.fill" : "rectangle.on.rectangle")
                        .foregroundStyle(viewModel.displayTone.color)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.displayStatusText)
                            .font(.headline)
                        Text("If the layout was not restored, retry it or open Display Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    Button("Retry layout") {
                        viewModel.retryDisplayLayout()
                    }
                    .buttonStyle(.bordered)
                    Button("Open Display Settings") {
                        viewModel.openDisplaySettings()
                    }
                    .buttonStyle(.link)
                }
            }

            Panel {
                PanelHeader(
                    title: "System settings",
                    subtitle: "Open the relevant macOS pane without hunting through System Settings."
                )
                HStack(spacing: 10) {
                    Button("Bluetooth") {
                        viewModel.openBluetoothSettings()
                    }
                    .buttonStyle(.bordered)
                    Button("Displays") {
                        viewModel.openDisplaySettings()
                    }
                    .buttonStyle(.bordered)
                    Button("Login Items") {
                        viewModel.openLoginSettings()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Panel {
                PanelHeader(
                    title: "About getkbd",
                    subtitle: "A small utility for sharing one Bluetooth keyboard between two Macs."
                )
                HStack {
                    Text("Version")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("0.1.0")
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.message.isEmpty {
                InlineNotice(text: viewModel.message, tone: .warning)
            }
        }
    }
}

private struct PeerPanel: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Panel {
            PanelHeader(
                title: "Other Mac",
                subtitle: "Pair with the other getkbd instance to verify the input signal and test the handoff."
            )

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: viewModel.peerConnectionIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(viewModel.peerConnectionTone.color)
                    .frame(width: 38, height: 38)
                    .background(viewModel.peerConnectionTone.background)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.peerStatusText)
                        .font(.headline)
                    Text(viewModel.peerConnectionDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                StatusPill(text: viewModel.peerVerificationText, tone: viewModel.peerVerificationTone)
            }

            if !viewModel.isPeerPaired {
                if !viewModel.discoveredPeers.isEmpty {
                    Picker("Other Mac", selection: $viewModel.selectedPeerIndex) {
                        ForEach(viewModel.discoveredPeers.indices, id: \.self) { index in
                            Text(viewModel.discoveredPeers[index]).tag(index)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                } else {
                    Text("No other Mac found yet. Open getkbd on the other Mac and wait a moment.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button(viewModel.peerActionTitle) {
                    viewModel.connectToPeer()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.peerActionEnabled)

                if viewModel.peerConnectionState == .awaitingConfirmation,
                   let code = viewModel.pairingCode {
                    Text("Code \(code)")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }

            if viewModel.peerConnectionState == .awaitingConfirmation {
                InlineNotice(
                    text: "Compare the code on both Macs, then confirm pairing on each one.",
                    tone: .accent
                )
                Button("Confirm pairing") {
                    viewModel.confirmPairing()
                }
                .buttonStyle(.bordered)
            }

            if !viewModel.peerMessage.isEmpty {
                Text(viewModel.peerMessage)
                    .font(.caption)
                    .foregroundStyle(viewModel.peerVerificationTone == .critical ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: viewModel.peerVerificationStatus == .unsafe ? "exclamationmark.triangle.fill" : "checkmark.shield")
                    .foregroundStyle(viewModel.peerVerificationStatus == .unsafe ? .red : .secondary)
                Text(viewModel.peerSafetyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct HubPanel: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showingManualSelection = false

    var body: some View {
        Panel {
            PanelHeader(
                title: "Input signal",
                subtitle: "Find the USB connection that appears only on the Mac selected by the monitor input."
            )

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "cable.connector")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(viewModel.hubTone.color)
                    .frame(width: 38, height: 38)
                    .background(viewModel.hubTone.background)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.hubStatusText)
                        .font(.headline)
                    Text(viewModel.hubDetectionDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                StatusPill(text: viewModel.hubStatusText, tone: viewModel.hubTone)
            }

            HStack(spacing: 10) {
                Button(viewModel.hubDetectionTitle) {
                    viewModel.identifyHub()
                }
                .buttonStyle(.borderedProminent)

                Button("Choose manually") {
                    showingManualSelection.toggle()
                }
                .buttonStyle(.bordered)
            }

            if showingManualSelection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("USB hub")
                        .font(.subheadline.weight(.semibold))
                    Picker("USB hub", selection: Binding(
                        get: { viewModel.settings.selectedUSBHub?.identifier ?? "" },
                        set: { viewModel.selectHub(identifier: $0) }
                    )) {
                        Text(viewModel.hubOptions.isEmpty ? "No USB hubs detected" : "Select a USB hub")
                            .tag("")
                        ForEach(viewModel.hubOptions) { hub in
                            Text(hub.menuTitle).tag(hub.identifier)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 4)
            }

            if !viewModel.hubIdentificationMessage.isEmpty {
                Text(viewModel.hubIdentificationMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct TestPanel: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Panel {
            PanelHeader(
                title: "Test the handoff",
                subtitle: "A quick two-way test confirms that the keyboard and display layout move safely."
            )

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(viewModel.kvmTestTone.color)
                    .frame(width: 38, height: 38)
                    .background(viewModel.kvmTestTone.background)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.peerTestStatus.uiTitle)
                        .font(.headline)
                    Text(viewModel.kvmTestDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                StatusPill(text: viewModel.peerTestStatus.uiTitle, tone: viewModel.kvmTestTone)
            }

            HStack(spacing: 10) {
                Button("Test switching") {
                    viewModel.testSwitching()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!(viewModel.isPeerConnected && viewModel.peerVerificationStatus == .verified))

                Button("Continue without testing") {
                    viewModel.skipSwitchingTest()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.settings.selectedUSBHub == nil)
            }
        }
    }
}

private struct KeyboardDeviceRow: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .frame(width: 36, height: 36)
                .background(Color(nsColor: .controlAccentColor).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("Shared keyboard")
                    .font(.headline)
                Text(viewModel.settings.selectedKeyboard?.name ?? "Select the Bluetooth keyboard used by both Macs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
            .frame(width: 260, alignment: .trailing)
        }

        HStack(spacing: 8) {
            StatusPill(
                text: viewModel.keyboardState.menuTitle,
                tone: viewModel.isKeyboardConnected ? .positive : .warning
            )
            Button("Open Bluetooth") {
                viewModel.openBluetoothSettings()
            }
            .buttonStyle(.link)
        }
    }
}

private struct DisplayDeviceRow: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(nsColor: .controlAccentColor))
                .frame(width: 36, height: 36)
                .background(Color(nsColor: .controlAccentColor).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("Shared display")
                    .font(.headline)
                Text(viewModel.settings.selectedDisplay?.name ?? "Select the external display used at the desk")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Display", selection: Binding(
                get: { viewModel.settings.selectedDisplay?.identifier ?? "" },
                set: { viewModel.selectDisplay(identifier: $0) }
            )) {
                if viewModel.displayOptions.isEmpty {
                    Text("No external displays found").tag("")
                } else {
                    Text("Select a display").tag("")
                    ForEach(viewModel.displayOptions) { display in
                        Text(display.name).tag(display.identifier)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 260, alignment: .trailing)
        }

        HStack(spacing: 8) {
            StatusPill(text: viewModel.displayStatusText, tone: viewModel.displayTone)
            Button("Open Displays") {
                viewModel.openDisplaySettings()
            }
            .buttonStyle(.link)
        }
    }
}

private struct SourceChoice: View {
    let source: AutomaticSource
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: source.systemImage)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(isSelected ? Color(nsColor: .controlAccentColor) : .secondary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(nsColor: .controlAccentColor))
                    }
                }
                Text(source.uiTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(source.uiDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .padding(15)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected
                        ? Color(nsColor: .controlAccentColor).opacity(0.11)
                        : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected
                            ? Color(nsColor: .controlAccentColor).opacity(0.7)
                            : Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PageScroll<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(Color(nsColor: .controlAccentColor))
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 720, alignment: .leading)
    }
}

private struct Panel<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        )
    }
}

private struct PanelHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ReadinessCard: View {
    let readiness: SettingsReadiness
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: readiness.systemImage)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(readiness.tone.color)
                .frame(width: 50, height: 50)
                .background(readiness.tone.background)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(readiness.title)
                    .font(.title3.weight(.semibold))
                Text(readiness.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(readiness.actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(readiness.tone.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(readiness.tone.color.opacity(0.28), lineWidth: 1)
        )
    }
}

private struct StatusTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tone: StatusTone

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tone.color)
                .frame(width: 34, height: 34)
                .background(tone.background)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .lineLimit(2)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 1)
        )
    }
}

private struct StatusPill: View {
    let text: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone.color)
                .frame(width: 7, height: 7)
            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tone.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tone.background)
        .clipShape(Capsule())
    }
}

private struct InlineNotice: View {
    let text: String
    let tone: StatusTone

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone == .critical ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(tone.color)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DetailRow: View {
    let title: String
    let value: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }
    }
}

private extension AutomaticSource {
    var uiTitle: String {
        switch self {
        case .monitor: return "Swap the display cable"
        case .usbHub: return "Change the monitor input"
        case .off: return "Switch manually"
        }
    }

    var uiDescription: String {
        switch self {
        case .monitor: return "Move one cable between Macs."
        case .usbHub: return "Keep both Macs connected."
        case .off: return "Use the menu bar or shortcut."
        }
    }

    var systemImage: String {
        switch self {
        case .monitor: return "arrow.left.arrow.right"
        case .usbHub: return "rectangle.on.rectangle"
        case .off: return "hand.tap"
        }
    }
}

private extension KVMTestStatus {
    var uiTitle: String {
        switch self {
        case .notStarted: return "Not tested"
        case .waitingForFirstSwitch: return "Waiting for first switch"
        case .waitingForReturn: return "Waiting to switch back"
        case .passed: return "Test passed"
        case .skipped: return "Not verified"
        case .failed: return "Test failed"
        }
    }
}
