import AppKit
import Carbon
import Foundation

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settingsStore: SettingsStore
    private let keyboard: KeyboardControlling
    private let usbHub: USBHubMonitor
    private let displayMonitor: DisplayMonitor
    private let ownership: OwnershipController
    private let peer: PeerVerificationController
    private let onChange: (AppSettings) -> Void

    private let readinessLabel = NSTextField(labelWithString: "")
    private let readinessDetailLabel = NSTextField(labelWithString: "")
    private let keyboardPopup = NSPopUpButton()
    private let displayPopup = NSPopUpButton()
    private let usbHubPopup = NSPopUpButton()
    private let keyboardStateLabel = NSTextField(labelWithString: "")
    private let displayStateLabel = NSTextField(labelWithString: "")
    private let displayRecoveryButton = NSButton(title: "Restore Display Layout", target: nil, action: nil)
    private let hubStateLabel = NSTextField(labelWithString: "")
    private let automaticSourcePopup = NSPopUpButton()
    private let automaticSourceHelpLabel = NSTextField(labelWithString: "")
    private let identifyUSBHubButton = NSButton(title: "Detect Monitor Input Signal", target: nil, action: nil)
    private let usbHubIdentificationLabel = NSTextField(labelWithString: "")
    private let peerStatusLabel = NSTextField(labelWithString: "")
    private let peerVerificationLabel = NSTextField(labelWithString: "")
    private let kvmSafetyLabel = NSTextField(labelWithString: "")
    private let pairingCodeLabel = NSTextField(labelWithString: "")
    private let peerPopup = NSPopUpButton()
    private let peerActionButton = NSButton(title: "Find Other Mac", target: nil, action: nil)
    private let confirmPairingButton = NSButton(title: "Confirm Pairing", target: nil, action: nil)
    private let kvmTestButton = NSButton(title: "Test Switching", target: nil, action: nil)
    private let skipKVMTestButton = NSButton(title: "Continue Without Testing", target: nil, action: nil)
    private let kvmTestLabel = NSTextField(labelWithString: "")
    private let autoClaimCheckbox = NSButton(checkboxWithTitle: "Get keyboard when monitor connects", target: nil, action: nil)
    private let monitorOwnershipCheckbox = NSButton(
        checkboxWithTitle: "Let the monitor take ownership after a manual claim",
        target: nil,
        action: nil
    )
    private let autoReleaseCheckbox = NSButton(checkboxWithTitle: "Release keyboard when monitor disconnects", target: nil, action: nil)
    private let sleepCheckbox = NSButton(checkboxWithTitle: "Release keyboard before sleep", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch getkbd at login", target: nil, action: nil)
    private let loginStatusLabel = NSTextField(labelWithString: "")
    private let shortcutButton = NSButton(title: "", target: nil, action: nil)
    private let messageLabel = NSTextField(labelWithString: "")

    private var displaySectionViews: [NSView] = []
    private var usbHubSectionViews: [NSView] = []
    private var peerSectionViews: [NSView] = []
    private var latestSnapshot: OwnershipSnapshot?
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

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "getkbd Settings"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        buildView()
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAndFocus() {
        reload()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func reload() {
        let settings = settingsStore.value
        usbHubIdentificationLabel.stringValue = ""
        identifyUSBHubButton.title = "Detect Monitor Input Signal"
        hubIdentificationBaseline = nil
        messageLabel.stringValue = ""
        keyboardLoadTask?.cancel()
        reloadKeyboardPopup(selected: settings.selectedKeyboard, devices: nil)
        reloadDisplayPopup(selected: settings.selectedDisplay)
        reloadUSBHubPopup(selected: settings.selectedUSBHub)
        reloadAutomaticSourcePopup(selected: settings.automaticSource)

        keyboardStateLabel.stringValue = keyboard.state.menuTitle
        updateConditionLabels()
        autoClaimCheckbox.state = settings.claimOnMonitorConnect ? .on : .off
        monitorOwnershipCheckbox.state = settings.monitorTakesOwnershipFromManual ? .on : .off
        autoReleaseCheckbox.state = settings.releaseOnMonitorDisconnect ? .on : .off
        sleepCheckbox.state = settings.releaseBeforeSleep ? .on : .off
        loginCheckbox.state = settings.launchAtLogin ? .on : .off
        shortcutButton.title = settings.shortcut.displayString
        updateAutomaticSourceControls(for: settings.automaticSource)
        loginStatusLabel.stringValue = LoginItemController.statusDescription()
        refreshPeerState()
        updateReadiness()

        keyboardLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let devices = await self.keyboard.availableKeyboards()
            guard !Task.isCancelled else { return }
            self.reloadKeyboardPopup(
                selected: self.settingsStore.value.selectedKeyboard,
                devices: devices
            )
        }
    }

    func update(snapshot: OwnershipSnapshot) {
        latestSnapshot = snapshot
        keyboardStateLabel.stringValue = snapshot.keyboardState.menuTitle
        updateConditionLabels()
        updateReadiness()
    }

    func refreshPeerState() {
        applyDetectedHubIfNeeded()
        peerStatusLabel.stringValue = peer.peerDetail
        peerVerificationLabel.stringValue = "Signal: \(peer.verificationTitle)"
        if peer.verificationStatus == .unsafe {
            kvmSafetyLabel.stringValue = "Safety check failed: both Macs can see this USB connection. Automatic switching is unsafe."
            kvmSafetyLabel.textColor = .systemRed
        } else {
            kvmSafetyLabel.stringValue = "The selected USB connection should appear on one Mac at a time."
            kvmSafetyLabel.textColor = .secondaryLabelColor
        }
        pairingCodeLabel.stringValue = peer.pairingCode.map { "Confirm code \($0) on both Macs." } ?? ""
        kvmTestLabel.stringValue = peer.kvmTestTitle

        peerPopup.removeAllItems()
        if peer.isPaired {
            peerPopup.addItem(withTitle: peer.peerName ?? "Paired Other Mac")
            peerPopup.isEnabled = false
        } else if peer.discoveredPeerSummaries.isEmpty {
            peerPopup.addItem(withTitle: "No other Macs found yet")
            peerPopup.item(at: 0)?.isEnabled = false
            peerPopup.isEnabled = false
        } else {
            peer.discoveredPeerSummaries.forEach { peerPopup.addItem(withTitle: $0) }
            peerPopup.isEnabled = true
        }

        if !peer.isPaired, !peer.hasDiscoveredPeer {
            peerStatusLabel.stringValue = "Open getkbd on the other Mac and keep both Macs on the same network."
        }

        if peer.isPaired {
            peerActionButton.title = "Forget Other Mac"
        } else if peer.discoveredPeerSummaries.count == 1,
                  let discoveredPeerName = peer.discoveredPeerName {
            peerActionButton.title = "Connect to \(discoveredPeerName)"
        } else if peer.hasDiscoveredPeer {
            peerActionButton.title = "Connect to Selected Mac"
        } else {
            peerActionButton.title = "Find Other Mac"
        }

        confirmPairingButton.isHidden = peer.connectionState != .awaitingConfirmation
        pairingCodeLabel.isHidden = peer.connectionState != .awaitingConfirmation
        peerActionButton.isEnabled = peer.isPaired || peer.hasDiscoveredPeer
        kvmTestButton.isEnabled = peer.isPeerConnected && peer.verificationStatus == .verified
        skipKVMTestButton.isEnabled = settingsStore.value.selectedUSBHub != nil

        if peer.isPeerConnected, peer.verificationStatus == .listening {
            identifyUSBHubButton.title = "Finish Detection"
        } else if hubIdentificationBaseline == nil {
            identifyUSBHubButton.title = "Detect Monitor Input Signal"
        }

        if let message = peer.lastMessage, !message.isEmpty {
            messageLabel.stringValue = message
        }
        updateReadiness()
    }

    private func applyDetectedHubIfNeeded() {
        guard peer.verificationStatus == .verified,
              let descriptor = peer.detectedHub,
              settingsStore.value.selectedUSBHub?.identifier != descriptor.identifier else {
            return
        }

        var settings = settingsStore.value
        settings.selectedUSBHub = descriptor
        commit(settings)
        reloadUSBHubPopup(selected: descriptor)
        usbHubIdentificationLabel.stringValue = "Detected the monitor input signal: \(descriptor.menuTitle)."
    }

    private func updateConditionLabels() {
        let snapshot = latestSnapshot
        let monitorPresent = snapshot?.monitorPresent ?? displayMonitor.isPresent
        let hubPresent = snapshot?.usbHubPresent ?? usbHub.isPresent
        let monitorStatus = monitorPresent ? "Connected" : "Not currently connected"
        if let handoffState = snapshot?.displayHandoffState,
           handoffState != .idle {
            displayStateLabel.stringValue = "\(monitorStatus) - \(handoffState.menuTitle)"
        } else {
            displayStateLabel.stringValue = monitorStatus
        }
        displayRecoveryButton.isHidden = snapshot?.displayHandoffState != .attentionRequired
        hubStateLabel.stringValue = hubPresent ? "Connected" : "Not currently connected"
    }

    func showMessage(_ message: String) {
        messageLabel.stringValue = message
    }

    func windowWillClose(_ notification: Notification) {
        removeShortcutMonitor()
        keyboardLoadTask?.cancel()
        keyboardLoadTask = nil
        hubIdentificationBaseline = nil
    }

    func usbHubListChanged() {
        reloadUSBHubPopup(selected: settingsStore.value.selectedUSBHub)

        if peer.verificationStatus == .verified,
           let descriptor = peer.detectedHub,
           settingsStore.value.selectedUSBHub?.identifier != descriptor.identifier {
            var settings = settingsStore.value
            settings.selectedUSBHub = descriptor
            commit(settings)
            reloadUSBHubPopup(selected: descriptor)
            usbHubIdentificationLabel.stringValue = "Detected the monitor input signal: \(descriptor.menuTitle)."
        }

        guard let baseline = hubIdentificationBaseline else { return }
        let current = Dictionary(usbHub.availableHubs.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let changedIdentifiers = Set(baseline.keys).symmetricDifference(current.keys)
        let candidates = changedIdentifiers.compactMap { current[$0] ?? baseline[$0] }
        guard candidates.count == 1,
              let descriptor = candidates.first else {
            guard changedIdentifiers.isEmpty else {
                hubIdentificationBaseline = nil
                identifyUSBHubButton.title = "Detect Monitor Input Signal"
                usbHubIdentificationLabel.stringValue = "Several hubs changed. Select the KVM hub manually."
                return
            }
            return
        }

        hubIdentificationBaseline = nil
        identifyUSBHubButton.title = "Detect Monitor Input Signal"
        var settings = settingsStore.value
        settings.selectedUSBHub = descriptor
        commit(settings)
        reloadUSBHubPopup(selected: descriptor)
        usbHubIdentificationLabel.stringValue = "Detected \(descriptor.menuTitle)."
    }

    private func buildView() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        contentView.addSubview(scrollView)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        readinessLabel.font = NSFont.boldSystemFont(ofSize: 16)
        readinessLabel.textColor = .labelColor
        stack.addArrangedSubview(readinessLabel)
        readinessDetailLabel.textColor = .secondaryLabelColor
        readinessDetailLabel.maximumNumberOfLines = 0
        stack.addArrangedSubview(readinessDetailLabel)

        stack.addArrangedSubview(sectionTitle("Keyboard"))
        stack.addArrangedSubview(fieldLabel("Paired keyboard"))
        keyboardPopup.target = self
        keyboardPopup.action = #selector(keyboardChanged)
        keyboardPopup.widthAnchor.constraint(equalToConstant: 390).isActive = true
        stack.addArrangedSubview(keyboardPopup)
        keyboardStateLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(keyboardStateLabel)
        let openBluetoothButton = NSButton(
            title: "Open Bluetooth Settings",
            target: self,
            action: #selector(openBluetoothSettings)
        )
        openBluetoothButton.bezelStyle = .rounded
        stack.addArrangedSubview(openBluetoothButton)

        let displayTitle = sectionTitle("Shared Monitor")
        let displayDescription = fieldLabel("External display used as the desk connection")
        stack.addArrangedSubview(displayTitle)
        stack.addArrangedSubview(displayDescription)
        displayPopup.target = self
        displayPopup.action = #selector(displayChanged)
        displayPopup.widthAnchor.constraint(equalToConstant: 390).isActive = true
        stack.addArrangedSubview(displayPopup)
        displayStateLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(displayStateLabel)
        let openDisplayButton = NSButton(
            title: "Open Display Settings",
            target: self,
            action: #selector(openDisplaySettings)
        )
        openDisplayButton.bezelStyle = .rounded
        stack.addArrangedSubview(openDisplayButton)
        displayRecoveryButton.bezelStyle = .rounded
        displayRecoveryButton.target = self
        displayRecoveryButton.action = #selector(retryDisplayLayout)
        displayRecoveryButton.isHidden = true
        stack.addArrangedSubview(displayRecoveryButton)
        displaySectionViews = [
            displayTitle,
            displayDescription,
            displayPopup,
            displayStateLabel,
            openDisplayButton,
            displayRecoveryButton
        ]

        let refreshButton = NSButton(
            title: "Refresh Keyboard, Monitor, and USB Hub Lists",
            target: self,
            action: #selector(refreshSelectors)
        )
        refreshButton.bezelStyle = .rounded
        stack.addArrangedSubview(refreshButton)

        let hubTitle = sectionTitle("Monitor Input Signal")
        let hubDescription = fieldLabel("A USB connection that follows the selected monitor input")
        stack.addArrangedSubview(hubTitle)
        stack.addArrangedSubview(hubDescription)
        usbHubPopup.target = self
        usbHubPopup.action = #selector(usbHubChanged)
        usbHubPopup.widthAnchor.constraint(equalToConstant: 390).isActive = true
        stack.addArrangedSubview(usbHubPopup)
        hubStateLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hubStateLabel)
        identifyUSBHubButton.bezelStyle = .rounded
        identifyUSBHubButton.target = self
        identifyUSBHubButton.action = #selector(identifyUSBHub)
        stack.addArrangedSubview(identifyUSBHubButton)
        usbHubIdentificationLabel.textColor = .secondaryLabelColor
        usbHubIdentificationLabel.maximumNumberOfLines = 0
        stack.addArrangedSubview(usbHubIdentificationLabel)
        usbHubSectionViews = [hubTitle, hubDescription, usbHubPopup, hubStateLabel, identifyUSBHubButton, usbHubIdentificationLabel]

        let peerTitle = sectionTitle("Other Mac")
        stack.addArrangedSubview(peerTitle)
        peerPopup.widthAnchor.constraint(equalToConstant: 390).isActive = true
        stack.addArrangedSubview(peerPopup)
        peerStatusLabel.textColor = .secondaryLabelColor
        peerStatusLabel.maximumNumberOfLines = 0
        stack.addArrangedSubview(peerStatusLabel)
        peerVerificationLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(peerVerificationLabel)
        kvmSafetyLabel.textColor = .secondaryLabelColor
        kvmSafetyLabel.maximumNumberOfLines = 0
        stack.addArrangedSubview(kvmSafetyLabel)
        pairingCodeLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        pairingCodeLabel.textColor = .labelColor
        pairingCodeLabel.maximumNumberOfLines = 0
        stack.addArrangedSubview(pairingCodeLabel)
        peerActionButton.bezelStyle = .rounded
        peerActionButton.target = self
        peerActionButton.action = #selector(peerAction)
        stack.addArrangedSubview(peerActionButton)
        confirmPairingButton.bezelStyle = .rounded
        confirmPairingButton.target = self
        confirmPairingButton.action = #selector(confirmPairing)
        stack.addArrangedSubview(confirmPairingButton)

        kvmTestButton.bezelStyle = .rounded
        kvmTestButton.target = self
        kvmTestButton.action = #selector(testSwitching)
        stack.addArrangedSubview(kvmTestButton)
        kvmTestLabel.textColor = .secondaryLabelColor
        kvmTestLabel.maximumNumberOfLines = 0
        stack.addArrangedSubview(kvmTestLabel)
        skipKVMTestButton.bezelStyle = .rounded
        skipKVMTestButton.target = self
        skipKVMTestButton.action = #selector(skipSwitchingTest)
        stack.addArrangedSubview(skipKVMTestButton)
        peerSectionViews = [
            peerTitle,
            peerPopup,
            peerStatusLabel,
            peerVerificationLabel,
            kvmSafetyLabel,
            pairingCodeLabel,
            peerActionButton,
            confirmPairingButton,
            kvmTestButton,
            kvmTestLabel,
            skipKVMTestButton
        ]

        stack.addArrangedSubview(sectionTitle("How Switching Works"))
        stack.addArrangedSubview(fieldLabel("Switching method"))
        automaticSourcePopup.target = self
        automaticSourcePopup.action = #selector(automaticSourceChanged)
        automaticSourcePopup.widthAnchor.constraint(equalToConstant: 390).isActive = true
        stack.addArrangedSubview(automaticSourcePopup)
        automaticSourceHelpLabel.textColor = .secondaryLabelColor
        automaticSourceHelpLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(automaticSourceHelpLabel)
        autoClaimCheckbox.target = self
        autoClaimCheckbox.action = #selector(behaviorChanged)
        monitorOwnershipCheckbox.target = self
        monitorOwnershipCheckbox.action = #selector(behaviorChanged)
        autoReleaseCheckbox.target = self
        autoReleaseCheckbox.action = #selector(behaviorChanged)
        sleepCheckbox.target = self
        sleepCheckbox.action = #selector(behaviorChanged)
        stack.addArrangedSubview(autoClaimCheckbox)
        stack.addArrangedSubview(monitorOwnershipCheckbox)
        stack.addArrangedSubview(autoReleaseCheckbox)
        stack.addArrangedSubview(sleepCheckbox)

        stack.addArrangedSubview(sectionTitle("Shortcut"))
        shortcutButton.target = self
        shortcutButton.action = #selector(recordShortcut)
        shortcutButton.bezelStyle = .rounded
        shortcutButton.widthAnchor.constraint(equalToConstant: 220).isActive = true
        stack.addArrangedSubview(shortcutButton)

        stack.addArrangedSubview(sectionTitle("Startup"))
        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginChanged)
        stack.addArrangedSubview(loginCheckbox)
        loginStatusLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(loginStatusLabel)

        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 0
        stack.addArrangedSubview(messageLabel)
    }

    private func reloadKeyboardPopup(
        selected: KeyboardDescriptor?,
        devices: [KeyboardDescriptor]?
    ) {
        keyboardPopup.removeAllItems()
        guard let devices else {
            keyboardPopup.addItem(withTitle: "Loading paired Bluetooth keyboards...")
            keyboardPopup.item(at: 0)?.isEnabled = false
            return
        }

        var displayedDevices = devices
        if let selected,
           !displayedDevices.contains(where: { $0.identifier == selected.identifier }) {
            displayedDevices.insert(selected, at: 0)
        }

        if displayedDevices.isEmpty {
            keyboardPopup.addItem(withTitle: "No paired Bluetooth keyboards found")
            keyboardPopup.item(at: 0)?.isEnabled = false
            return
        }

        displayedDevices.forEach { device in
            let isPresent = devices.contains { $0.identifier == device.identifier }
            let title = isPresent ? device.name : "\(device.name) (not currently paired)"
            keyboardPopup.addItem(withTitle: title)
            keyboardPopup.lastItem?.representedObject = device
            keyboardPopup.lastItem?.isEnabled = isPresent
        }

        if let selected,
           let index = displayedDevices.firstIndex(where: { $0.identifier == selected.identifier }) {
            keyboardPopup.selectItem(at: index)
        } else {
            keyboardPopup.select(nil)
        }
    }

    private func reloadDisplayPopup(selected: DisplayDescriptor?) {
        displayPopup.removeAllItems()
        let currentDisplays = DisplayMonitor.currentDisplays()
        var displays = currentDisplays.filter { !$0.isBuiltIn }

        if let selected,
           !selected.isBuiltIn,
           !displays.contains(where: { $0.identifier == selected.identifier }) {
            displays.insert(selected, at: 0)
        }

        if displays.isEmpty {
            displayPopup.addItem(withTitle: "No external displays currently connected")
            displayPopup.item(at: 0)?.isEnabled = false
            return
        }

        displays.forEach { display in
            let isPresent = currentDisplays.contains { $0.identifier == display.identifier }
            let title = isPresent ? display.name : "\(display.name) (not currently connected)"
            displayPopup.addItem(withTitle: title)
            displayPopup.lastItem?.representedObject = display
        }

        if let selected,
           let index = displays.firstIndex(where: { $0.identifier == selected.identifier }) {
            displayPopup.selectItem(at: index)
        } else {
            displayPopup.select(nil)
        }
    }

    private func reloadUSBHubPopup(selected: USBHubDescriptor?) {
        usbHubPopup.removeAllItems()
        var hubs = usbHub.availableHubs

        if let selected,
           !hubs.contains(where: { $0.identifier == selected.identifier }) {
            hubs.insert(selected, at: 0)
        }

        if hubs.isEmpty {
            usbHubPopup.addItem(withTitle: "No USB hubs currently detected")
            usbHubPopup.item(at: 0)?.isEnabled = false
            return
        }

        hubs.forEach { hub in
            let isPresent = usbHub.availableHubs.contains { $0.identifier == hub.identifier }
            let title = isPresent ? hub.menuTitle : "\(hub.menuTitle) (not currently connected)"
            usbHubPopup.addItem(withTitle: title)
            usbHubPopup.lastItem?.representedObject = hub
        }

        if let selected,
           let index = hubs.firstIndex(where: { $0.identifier == selected.identifier }) {
            usbHubPopup.selectItem(at: index)
        } else {
            usbHubPopup.select(nil)
        }
    }

    private func reloadAutomaticSourcePopup(selected: AutomaticSource) {
        automaticSourcePopup.removeAllItems()
        [AutomaticSource.monitor, .usbHub, .off].forEach { source in
            automaticSourcePopup.addItem(withTitle: source.setupTitle)
            automaticSourcePopup.lastItem?.representedObject = source
        }

        if let index = [AutomaticSource.monitor, .usbHub, .off].firstIndex(of: selected) {
            automaticSourcePopup.selectItem(at: index)
        }
    }

    private func updateAutomaticSourceControls(for source: AutomaticSource) {
        let usesMonitor = source == .monitor
        let usesDisplay = source != .off
        let usesUSBHub = source == .usbHub

        displaySectionViews.forEach { $0.isHidden = !usesDisplay }
        usbHubSectionViews.forEach { $0.isHidden = !usesUSBHub }
        peerSectionViews.forEach { $0.isHidden = !usesUSBHub }

        autoClaimCheckbox.isEnabled = usesMonitor
        monitorOwnershipCheckbox.isEnabled = usesMonitor && autoClaimCheckbox.state == .on
        autoReleaseCheckbox.isEnabled = usesMonitor
        autoClaimCheckbox.isHidden = !usesMonitor
        monitorOwnershipCheckbox.isHidden = !usesMonitor
        autoReleaseCheckbox.isHidden = !usesMonitor
        automaticSourceHelpLabel.stringValue = Self.automaticSourceHelp(for: source)
    }

    private static func automaticSourceHelp(for source: AutomaticSource) -> String {
        switch source {
        case .monitor:
            return "Use this when you physically unplug the display cable from one Mac and connect it to the other."
        case .usbHub:
            return "Use this when both Macs stay connected and you change the monitor input in software or on the display."
        case .off:
            return "Switch from the menu bar or with the configured keyboard shortcut."
        }
    }

    private func updateReadiness() {
        let settings = settingsStore.value

        guard settings.selectedKeyboard != nil else {
            readinessLabel.stringValue = "Needs setup"
            readinessDetailLabel.stringValue = "Select the shared Bluetooth keyboard to continue."
            return
        }

        switch settings.automaticSource {
        case .monitor:
            guard settings.selectedDisplay != nil else {
                readinessLabel.stringValue = "Needs setup"
                readinessDetailLabel.stringValue = "Select the external display you physically move between Macs."
                return
            }
            readinessLabel.stringValue = "Ready on this Mac"
            readinessDetailLabel.stringValue = "getkbd will watch the selected display connection. Repeat this setup on the other Mac."
        case .usbHub:
            guard settings.selectedDisplay != nil else {
                readinessLabel.stringValue = "Needs setup"
                readinessDetailLabel.stringValue = "Select the external display that changes when you switch inputs."
                return
            }
            guard settings.selectedUSBHub != nil else {
                readinessLabel.stringValue = "Needs setup"
                readinessDetailLabel.stringValue = "Detect the USB connection that follows the monitor input."
                return
            }
            guard peer.isPaired else {
                readinessLabel.stringValue = "Ready locally, not verified"
                readinessDetailLabel.stringValue = "Pair the other Mac to verify that the USB connection follows the monitor input."
                return
            }
            if peer.verificationStatus == .unsafe {
                readinessLabel.stringValue = "Needs attention"
                readinessDetailLabel.stringValue = "Both Macs can see this USB connection. Automatic switching is unsafe."
                return
            }
            guard peer.verificationStatus == .verified else {
                readinessLabel.stringValue = "Verify the monitor input"
                readinessDetailLabel.stringValue = peer.verificationTitle
                return
            }
            guard peer.kvmTestStatus == .passed else {
                readinessLabel.stringValue = "Test the switch"
                readinessDetailLabel.stringValue = peer.kvmTestTitle
                return
            }
            readinessLabel.stringValue = "Ready on this Mac"
            readinessDetailLabel.stringValue = "Changing the monitor input will move the keyboard and protect your display layout."
        case .off:
            readinessLabel.stringValue = "Ready for manual switching"
            readinessDetailLabel.stringValue = "Use Get Keyboard, Release Keyboard, or the configured shortcut."
        }

        if let snapshot = latestSnapshot,
           snapshot.displayHandoffState == .attentionRequired,
           let error = snapshot.displayHandoffError {
            readinessLabel.stringValue = "Needs attention"
            readinessDetailLabel.stringValue = error
        }
    }

    private func sectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func fieldLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.textColor = .secondaryLabelColor
        return label
    }

    @objc private func keyboardChanged() {
        guard let descriptor = keyboardPopup.selectedItem?.representedObject as? KeyboardDescriptor else { return }
        var settings = settingsStore.value
        settings.selectedKeyboard = descriptor
        commit(settings)
        keyboardStateLabel.stringValue = keyboard.state.menuTitle
        updateReadiness()
    }

    @objc private func displayChanged() {
        guard let descriptor = displayPopup.selectedItem?.representedObject as? DisplayDescriptor else { return }
        var settings = settingsStore.value
        settings.selectedDisplay = descriptor
        commit(settings)
        updateReadiness()
    }

    @objc private func usbHubChanged() {
        guard let descriptor = usbHubPopup.selectedItem?.representedObject as? USBHubDescriptor else { return }
        var settings = settingsStore.value
        settings.selectedUSBHub = descriptor
        commit(settings)
        updateReadiness()
    }

    @objc private func identifyUSBHub() {
        if peer.isPeerConnected {
            if peer.verificationStatus == .listening {
                peer.finishHubDetection()
                identifyUSBHubButton.title = "Detect Monitor Input Signal"
                usbHubIdentificationLabel.stringValue = "No complementary USB hub transition was detected."
            } else {
                peer.beginHubDetection(localHubs: usbHub.availableHubs)
                identifyUSBHubButton.title = "Finish Detection"
                usbHubIdentificationLabel.stringValue = "Listening. Change the monitor input to the other Mac."
            }
            return
        }

        if hubIdentificationBaseline != nil {
            hubIdentificationBaseline = nil
            identifyUSBHubButton.title = "Detect Monitor Input Signal"
            usbHubIdentificationLabel.stringValue = ""
            return
        }

        hubIdentificationBaseline = Dictionary(
            usbHub.availableHubs.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        identifyUSBHubButton.title = "Cancel Identification"
        usbHubIdentificationLabel.stringValue = "Listening. Unplug or reconnect the display cable on the other Mac."
    }

    @objc private func peerAction() {
        if peer.isPaired {
            peer.forgetPeer()
        } else {
            peer.connectToDiscoveredPeer(at: peerPopup.indexOfSelectedItem)
        }
    }

    @objc private func confirmPairing() {
        peer.confirmPairing()
    }

    @objc private func testSwitching() {
        peer.startKVMTest()
    }

    @objc private func skipSwitchingTest() {
        peer.skipKVMTest()
    }

    @objc private func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openDisplaySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func retryDisplayLayout() {
        ownership.retryDisplayHandoff()
    }

    @objc private func automaticSourceChanged() {
        guard let source = automaticSourcePopup.selectedItem?.representedObject as? AutomaticSource else { return }
        var settings = settingsStore.value
        settings.automaticSource = source
        commit(settings)
        updateAutomaticSourceControls(for: source)
        updateReadiness()
    }

    @objc private func refreshSelectors() {
        reload()
    }

    @objc private func behaviorChanged() {
        var settings = settingsStore.value
        settings.claimOnMonitorConnect = autoClaimCheckbox.state == .on
        settings.monitorTakesOwnershipFromManual = monitorOwnershipCheckbox.state == .on
        settings.releaseOnMonitorDisconnect = autoReleaseCheckbox.state == .on
        settings.releaseBeforeSleep = sleepCheckbox.state == .on
        commit(settings)
        updateAutomaticSourceControls(for: settings.automaticSource)
        updateReadiness()
    }

    @objc private func loginChanged() {
        let enabled = loginCheckbox.state == .on
        guard LoginItemController.setEnabled(enabled) else {
            loginCheckbox.state = enabled ? .off : .on
            loginStatusLabel.stringValue = LoginItemController.statusDescription()
            messageLabel.stringValue = "Unable to update login item: \(loginStatusLabel.stringValue)."
            return
        }

        var settings = settingsStore.value
        settings.launchAtLogin = enabled
        commit(settings)
        loginStatusLabel.stringValue = LoginItemController.statusDescription()
    }

    @objc private func recordShortcut() {
        if shortcutMonitor != nil {
            removeShortcutMonitor()
            shortcutButton.title = settingsStore.value.shortcut.displayString
            return
        }

        shortcutButton.title = "Press keys..."
        messageLabel.stringValue = "Press at least one modifier and a key."
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
            shortcutButton.title = settingsStore.value.shortcut.displayString
            messageLabel.stringValue = ""
            return
        }

        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }

        guard modifiers != 0 else { return }

        var settings = settingsStore.value
        settings.shortcut = ShortcutConfiguration(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        removeShortcutMonitor()
        commit(settings)

        if settingsStore.value.shortcut == settings.shortcut {
            shortcutButton.title = settings.shortcut.displayString
            messageLabel.stringValue = ""
        }
    }

    private func removeShortcutMonitor() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
    }

    private func commit(_ settings: AppSettings) {
        onChange(settings)
    }
}
