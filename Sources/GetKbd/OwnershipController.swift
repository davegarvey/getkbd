import Foundation

@MainActor
final class OwnershipController {
    private let keyboard: KeyboardControlling
    private let displayHandoff: DisplayHandoffControlling?

    private(set) var snapshot: OwnershipSnapshot
    private(set) var desiredState: DesiredKeyboardState?

    var onChange: ((OwnershipSnapshot) -> Void)?

    private var behavior: AutomaticBehavior
    private var ownershipReason: OwnershipReason = .none
    private var monitorPresent = false
    private var usbHubPresent = false
    private var operationInProgress = false
    private var failedDesiredState: DesiredKeyboardState?
    private var lastError: String?
    private var pendingKeyboard: KeyboardDescriptor?
    private var hasPendingKeyboardConfiguration = false
    private var originalOwnershipReason = OwnershipReason.none
    private var reconfigurationReleaseAttempted = false
    private var isSleeping = false
    private var sleepOwnershipReason: OwnershipReason?
    private var automaticRetryTask: Task<Void, Never>?
    private var automaticRetryCount = 0
    private var kvmClaimIntent = false
    private var displayHandoffActive = false
    private var usbHubClaimTask: Task<Void, Never>?
    private static let usbHubClaimDelayNanoseconds: UInt64 = 750_000_000

    private var usesMonitorAutomation: Bool {
        behavior.automaticSource == .monitor
    }

    private var usesUSBHubAutomation: Bool {
        behavior.automaticSource == .usbHub
    }

    private var automaticClaimReady: Bool {
        switch behavior.automaticSource {
        case .monitor:
            return monitorPresent && behavior.claimOnMonitorConnect
        case .usbHub:
            return monitorPresent && usbHubPresent
        case .off:
            return false
        }
    }

    var onKeyboardReconfigurationFailure: ((String) -> Void)?

    init(
        keyboard: KeyboardControlling,
        behavior: AutomaticBehavior,
        displayHandoff: DisplayHandoffControlling? = nil
    ) {
        self.keyboard = keyboard
        self.behavior = behavior
        self.displayHandoff = displayHandoff
        self.snapshot = OwnershipSnapshot(
            keyboardState: keyboard.state,
            ownershipReason: .none,
            monitorPresent: false,
            usbHubPresent: false,
            isBusy: false,
            errorMessage: nil
        )

        keyboard.onStateChange = { [weak self] _ in
            self?.keyboardStateChanged()
        }
    }

    func start(monitorPresent: Bool, usbHubPresent: Bool = false) {
        self.monitorPresent = monitorPresent
        self.usbHubPresent = usbHubPresent
        kvmClaimIntent = false
        keyboard.refreshState()

        if usesUSBHubAutomation {
            desiredState = automaticClaimReady ? .connected : .disconnected
            if keyboard.state == .connectedLocal || desiredState == .connected {
                ownershipReason = .usbHub
            } else {
                ownershipReason = .none
            }
            kvmClaimIntent = desiredState == .connected && keyboard.state != .connectedLocal
        } else if keyboard.state == .connectedLocal {
            ownershipReason = automaticClaimReady ? .monitor : .existing
            desiredState = .connected
        } else {
            let shouldClaim = automaticClaimReady
            ownershipReason = shouldClaim ? .monitor : .none
            desiredState = shouldClaim ? .connected : .disconnected
        }

        failedDesiredState = nil
        lastError = nil
        publish()
        if desiredState == .connected {
            restoreDisplayAfterKeyboardClaimIfNeeded()
        }
        if usesUSBHubAutomation && kvmClaimIntent {
            scheduleUSBHubClaim()
        } else if keyboard.state != .unknown {
            reconcile(force: desiredState == .connected)
        }
    }

    func updateBehavior(
        _ behavior: AutomaticBehavior,
        monitorPresent: Bool,
        usbHubPresent: Bool = false
    ) {
        self.behavior = behavior
        self.monitorPresent = monitorPresent
        self.usbHubPresent = usbHubPresent
        if behavior.automaticSource != .usbHub {
            kvmClaimIntent = false
            cancelUSBHubClaim()
        }

        if isSleeping {
            publish()
            return
        }

        if hasPendingKeyboardConfiguration {
            desiredState = automaticClaimReady ? .connected : .disconnected
            ownershipReason = desiredState == .connected
                ? (usesUSBHubAutomation ? .usbHub : .monitor)
                : .none
            failedDesiredState = nil
            lastError = nil
            publish()
            if !operationInProgress {
                beginReconfiguration()
            }
            return
        }

        if usesUSBHubAutomation {
            keyboard.refreshState()
            desiredState = automaticClaimReady ? .connected : .disconnected
            ownershipReason = keyboard.state == .connectedLocal || desiredState == .connected ? .usbHub : .none
            kvmClaimIntent = desiredState == .connected && keyboard.state != .connectedLocal
            failedDesiredState = nil
            automaticRetryCount = 0
            cancelAutomaticRetry()
            lastError = nil
            publish()
            if desiredState == .connected {
                restoreDisplayAfterKeyboardClaimIfNeeded()
            }
            if kvmClaimIntent {
                scheduleUSBHubClaim()
            } else {
                reconcile(force: true)
            }
            return
        }

        keyboard.refreshState()
        if usesMonitorAutomation,
           ownershipReason == .usbHub {
            ownershipReason = .monitor
        }
        if monitorPresent,
           usesMonitorAutomation,
           behavior.claimOnMonitorConnect,
           behavior.monitorTakesOwnershipFromManual,
           ownershipReason == .manual {
            ownershipReason = .monitor
        }

        if keyboard.state == .connectedLocal {
            if ownershipReason == .monitor,
               usesMonitorAutomation,
               !monitorPresent,
               behavior.releaseOnMonitorDisconnect {
                desiredState = .disconnected
            } else {
                desiredState = .connected
                if !usesMonitorAutomation,
                   (ownershipReason == .monitor || ownershipReason == .usbHub) {
                    ownershipReason = .existing
                } else if ownershipReason == .none {
                    ownershipReason = .existing
                }
            }
        } else if automaticClaimReady {
            desiredState = .connected
            if ownershipReason == .none || ownershipReason == .usbHub {
                ownershipReason = .monitor
            }
        } else {
            desiredState = .disconnected
            ownershipReason = .none
        }

        failedDesiredState = nil
        automaticRetryCount = 0
        cancelAutomaticRetry()
        lastError = nil
        publish()
        if desiredState == .connected {
            restoreDisplayAfterKeyboardClaimIfNeeded()
        }
        reconcile(force: true)
    }

    func monitorConnected() {
        monitorPresent = true
        automaticRetryCount = 0
        cancelAutomaticRetry()

        guard !isSleeping else {
            publish()
            return
        }

        restoreDisplayAfterKeyboardClaimIfNeeded()

        if usesUSBHubAutomation {
            if usbHubPresent {
                requestUSBHubClaim()
            } else {
                publish()
            }
            return
        }

        guard usesMonitorAutomation, behavior.claimOnMonitorConnect else {
            publish()
            return
        }

        desiredState = .connected
        failedDesiredState = nil

        if keyboard.state == .connectedLocal {
            if ownershipReason == .none {
                ownershipReason = .existing
            } else if ownershipReason == .manual,
                      behavior.monitorTakesOwnershipFromManual {
                ownershipReason = .monitor
            }
        } else if ownershipReason != .manual || behavior.monitorTakesOwnershipFromManual {
            ownershipReason = .monitor
        }

        GetKbdLog.event("monitor.connected")
        publish()
        restoreDisplayAfterKeyboardClaimIfNeeded()
        reconcile(force: true)
    }

    func monitorDisconnected() {
        monitorPresent = false
        cancelAutomaticRetry()
        automaticRetryCount = 0
        cancelUSBHubClaim()

        let releasesMonitorOwnedKeyboard = usesMonitorAutomation && ownershipReason == .monitor
        let releasesSelectedUSBKeyboard = usesUSBHubAutomation && keyboard.configuredKeyboard != nil
        guard (usesUSBHubAutomation || behavior.releaseOnMonitorDisconnect),
              (releasesMonitorOwnedKeyboard || releasesSelectedUSBKeyboard) else {
            publish()
            return
        }

        desiredState = .disconnected
        failedDesiredState = nil
        kvmClaimIntent = false
        if releasesSelectedUSBKeyboard {
            ownershipReason = .usbHub
        }
        GetKbdLog.event("monitor.disconnected")

        if keyboard.state == .disconnected && !operationInProgress {
            ownershipReason = .none
        }

        publish()
        reconcile(force: true)
    }

    func usbHubConnected() {
        usbHubPresent = true
        cancelAutomaticRetry()
        automaticRetryCount = 0

        guard !isSleeping else {
            publish()
            return
        }

        guard usesUSBHubAutomation else {
            publish()
            return
        }

        GetKbdLog.event("usb.hub.connected")
        if monitorPresent {
            requestUSBHubClaim()
        } else {
            publish()
        }
    }

    func usbHubDisconnected() {
        usbHubPresent = false
        cancelUSBHubClaim()
        cancelAutomaticRetry()
        automaticRetryCount = 0

        guard usesUSBHubAutomation else {
            publish()
            return
        }

        desiredState = .disconnected
        failedDesiredState = nil
        kvmClaimIntent = false
        ownershipReason = .usbHub
        lastError = nil
        GetKbdLog.event("usb.hub.disconnected")

        if keyboard.state == .disconnected && !operationInProgress {
            ownershipReason = .none
        }

        publish()
        reconcile(force: true)
    }

    private func requestUSBHubClaim() {
        guard usesUSBHubAutomation,
              monitorPresent,
              usbHubPresent else {
            return
        }

        keyboard.refreshState()
        kvmClaimIntent = keyboard.state != .connectedLocal
        cancelAutomaticRetry()
        automaticRetryCount = 0
        desiredState = .connected
        ownershipReason = .usbHub
        failedDesiredState = nil
        lastError = nil
        publish()
        restoreDisplayAfterKeyboardClaimIfNeeded()

        if kvmClaimIntent {
            scheduleUSBHubClaim()
        }
    }

    func manualClaim() {
        guard !isSleeping else { return }

        kvmClaimIntent = false
        cancelAutomaticRetry()
        automaticRetryCount = 0
        desiredState = .connected
        ownershipReason = .manual
        failedDesiredState = nil
        lastError = nil
        publish()
        restoreDisplayAfterKeyboardClaimIfNeeded()
        reconcile(force: true)
    }

    func manualRelease() {
        kvmClaimIntent = false
        cancelAutomaticRetry()
        automaticRetryCount = 0
        desiredState = .disconnected
        ownershipReason = .none
        failedDesiredState = nil
        lastError = nil
        publish()
        reconcile(force: true)
    }

    func willSleep() {
        let wasSleeping = isSleeping
        isSleeping = true
        if !wasSleeping {
            sleepOwnershipReason = behavior.releaseBeforeSleep ? ownershipReason : nil
        }

        if hasPendingKeyboardConfiguration {
            desiredState = .disconnected
            ownershipReason = .none
            failedDesiredState = nil
            lastError = nil
        }

        kvmClaimIntent = false
        cancelUSBHubClaim()
        guard behavior.releaseBeforeSleep else { return }

        cancelAutomaticRetry()
        automaticRetryCount = 0
        desiredState = .disconnected
        ownershipReason = .none
        failedDesiredState = nil
        lastError = nil
        publish()
        reconcile(force: true)
    }

    func didWake(monitorPresent: Bool) {
        isSleeping = false
        self.monitorPresent = monitorPresent
        cancelAutomaticRetry()
        automaticRetryCount = 0
        keyboard.refreshState()

        if hasPendingKeyboardConfiguration {
            sleepOwnershipReason = nil
            desiredState = automaticClaimReady ? .connected : .disconnected
            ownershipReason = desiredState == .connected
                ? (usesUSBHubAutomation ? .usbHub : .monitor)
                : .none
            failedDesiredState = nil
            lastError = nil
            publish()
            if !operationInProgress {
                beginReconfiguration()
            }
            return
        }

        if usesUSBHubAutomation {
            kvmClaimIntent = false
            sleepOwnershipReason = nil
            desiredState = automaticClaimReady ? .connected : .disconnected
            if keyboard.state == .connectedLocal || desiredState == .connected {
                ownershipReason = .usbHub
            } else {
                ownershipReason = .none
            }
            kvmClaimIntent = desiredState == .connected && keyboard.state != .connectedLocal
            publish()
            if desiredState == .connected {
                restoreDisplayAfterKeyboardClaimIfNeeded()
            }
            if kvmClaimIntent {
                scheduleUSBHubClaim()
            } else if !automaticClaimReady {
                reconcile(force: true)
            }
            return
        }

        if keyboard.state == .connectedLocal,
           let reasonBeforeSleep = sleepOwnershipReason,
           reasonBeforeSleep != .none {
            sleepOwnershipReason = nil
            ownershipReason = reasonBeforeSleep

            if reasonBeforeSleep == .manual,
                monitorPresent,
                usesMonitorAutomation,
                behavior.claimOnMonitorConnect,
               behavior.monitorTakesOwnershipFromManual {
                ownershipReason = .monitor
            }

            if ownershipReason == .monitor,
               !monitorPresent,
               usesMonitorAutomation,
               behavior.releaseOnMonitorDisconnect {
                desiredState = .disconnected
                failedDesiredState = nil
                publish()
                reconcile(force: true)
            } else {
                desiredState = .connected
                publish()
                restoreDisplayAfterKeyboardClaimIfNeeded()
            }
            return
        }

        sleepOwnershipReason = nil

        guard usesMonitorAutomation,
              monitorPresent,
              behavior.claimOnMonitorConnect else {
            if keyboard.state == .connectedLocal && ownershipReason == .none {
                ownershipReason = .existing
                desiredState = .connected
            }
            publish()
            if desiredState == .connected {
                restoreDisplayAfterKeyboardClaimIfNeeded()
            }
            return
        }

        if keyboard.state == .connectedLocal {
            desiredState = .connected
            if ownershipReason == .none {
                ownershipReason = .existing
            }
            publish()
            restoreDisplayAfterKeyboardClaimIfNeeded()
            return
        }

        desiredState = .connected
        ownershipReason = .monitor
        failedDesiredState = nil
        publish()
        reconcile(force: true)
    }

    func displayConfigurationChanged() {
        guard !isSleeping, !operationInProgress else { return }

        if keyboard.state == .connectedLocal,
           desiredState == .connected,
           displayHandoff?.hasPendingKeyboardRelease == true {
            restoreDisplayAfterKeyboardClaimIfNeeded()
        } else if desiredState == .disconnected, displayHandoffActive {
            displayHandoff?.prepareForKeyboardRelease()
        }
    }

    func keyboardStateChanged() {
        if keyboard.state == .connectedLocal {
            lastError = nil
            automaticRetryCount = 0
            cancelAutomaticRetry()
            if desiredState == nil {
                desiredState = .connected
                if ownershipReason == .none {
                    ownershipReason = .existing
                }
            }

            if desiredState == .connected, !operationInProgress {
                restoreDisplayAfterKeyboardClaimIfNeeded()
            }
        }

        publish()

        if keyboard.state == .connectedLocal,
           desiredState == .disconnected,
           ownershipReason == .usbHub,
           usesUSBHubAutomation,
           (!monitorPresent || !usbHubPresent),
           !operationInProgress {
            reconcile(force: true)
        }

        if (keyboard.state == .disconnected || keyboard.state == .failed),
           !operationInProgress {
            if desiredState == .connected,
               ownershipReason == .monitor,
               monitorPresent {
                scheduleAutomaticRetry(for: .connected)
            } else if desiredState == .connected,
                      ownershipReason == .usbHub,
                      usesUSBHubAutomation,
                      monitorPresent,
                      usbHubPresent,
                      kvmClaimIntent {
                scheduleAutomaticRetry(for: .connected)
            } else if desiredState == .disconnected,
                      ownershipReason == .monitor,
                      !monitorPresent,
                      behavior.releaseOnMonitorDisconnect {
                scheduleAutomaticRetry(for: .disconnected)
            } else if desiredState == .disconnected,
                      ownershipReason == .usbHub,
                      usesUSBHubAutomation,
                      (!monitorPresent || !usbHubPresent) {
                scheduleAutomaticRetry(for: .disconnected)
            }
        }
    }

    func reconfigureKeyboard(to descriptor: KeyboardDescriptor?, monitorPresent: Bool) {
        guard keyboard.configuredKeyboard != descriptor || hasPendingKeyboardConfiguration else {
            return
        }

        self.monitorPresent = monitorPresent
        kvmClaimIntent = false
        if !hasPendingKeyboardConfiguration {
            originalOwnershipReason = ownershipReason
            reconfigurationReleaseAttempted = false
        }
        pendingKeyboard = descriptor
        hasPendingKeyboardConfiguration = true
        desiredState = !isSleeping && automaticClaimReady ? .connected : .disconnected
        ownershipReason = desiredState == .connected
            ? (usesUSBHubAutomation ? .usbHub : .monitor)
            : .none
        failedDesiredState = nil
        lastError = nil
        cancelAutomaticRetry()
        automaticRetryCount = 0
        publish()

        if !operationInProgress && !isSleeping {
            beginReconfiguration()
        }
    }

    func waitForIdle() async {
        while operationInProgress || usbHubClaimTask != nil {
            await Task.yield()
        }
    }

    private func reconcile(force: Bool) {
        guard !operationInProgress,
              let desiredState else {
            return
        }

        let currentState = keyboard.state
        switch desiredState {
        case .connected:
            guard currentState != .connectedLocal,
                  currentState != .connecting,
                  currentState != .disconnecting else {
                return
            }
        case .disconnected:
            guard currentState != .disconnected,
                  currentState != .unknown,
                  currentState != .disconnecting,
                  currentState != .connecting else {
                return
            }
        }

        guard force || failedDesiredState != desiredState else { return }
        beginOperation(for: desiredState)
    }

    private func beginOperation(for target: DesiredKeyboardState) {
        if target == .disconnected {
            displayHandoffActive = true
            displayHandoff?.prepareForKeyboardRelease()
        }
        operationInProgress = true
        lastError = nil
        publish()

        Task { [weak self] in
            guard let self else { return }

            let succeeded: Bool
            switch target {
            case .connected:
                succeeded = await self.keyboard.connect()
            case .disconnected:
                succeeded = await self.keyboard.disconnect()
            }

            self.finishOperation(target: target, succeeded: succeeded)
        }
    }

    private func finishOperation(target: DesiredKeyboardState, succeeded: Bool) {
        operationInProgress = false

        if hasPendingKeyboardConfiguration {
            keyboard.refreshState()

            if isSleeping {
                if keyboard.state == .connectedLocal {
                    guard !reconfigurationReleaseAttempted else {
                        failReconfiguration("Unable to release the previous keyboard; the selection was not changed.")
                        return
                    }

                    reconfigurationReleaseAttempted = true
                    desiredState = .disconnected
                    ownershipReason = .none
                    failedDesiredState = nil
                    lastError = nil
                    beginOperation(for: .disconnected)
                } else {
                    publish()
                }
            } else if keyboard.state == .connectedLocal {
                guard !reconfigurationReleaseAttempted else {
                    failReconfiguration("Unable to release the previous keyboard; the selection was not changed.")
                    return
                }

                reconfigurationReleaseAttempted = true
                desiredState = .disconnected
                ownershipReason = .none
                failedDesiredState = nil
                lastError = nil
                publish()
                beginOperation(for: .disconnected)
            } else {
                applyPendingKeyboardConfiguration()
            }
            return
        }

        if succeeded {
            failedDesiredState = nil
            lastError = nil

            if target == .connected, ownershipReason == .usbHub {
                kvmClaimIntent = false
                cancelUSBHubClaim()
            }

            if target == .connected, desiredState == .connected {
                restoreDisplayAfterKeyboardClaimIfNeeded()
            }

            if target == .disconnected, desiredState == .disconnected {
                ownershipReason = .none
            } else if target == .connected,
                      desiredState == .connected,
                      ownershipReason == .none {
                ownershipReason = .existing
            }
        } else {
            if target == .disconnected {
                operationInProgress = true
                keyboard.refreshState()
                operationInProgress = false
            }
            if target == .disconnected, keyboard.state == .connectedLocal {
                displayHandoff?.restoreAfterKeyboardClaim()
                displayHandoffActive = displayHandoff?.hasPendingKeyboardRelease ?? false
            }
            failedDesiredState = target
            lastError = keyboard.lastError ?? "Bluetooth operation failed"
        }

        publish()

        if desiredState != target {
            failedDesiredState = nil
            reconcile(force: true)
        } else if !succeeded,
                  ((target == .connected && ownershipReason == .monitor && usesMonitorAutomation && monitorPresent) ||
                   (target == .connected && ownershipReason == .usbHub && usesUSBHubAutomation && automaticClaimReady && kvmClaimIntent) ||
                   (target == .disconnected && ownershipReason == .monitor && usesMonitorAutomation && !monitorPresent && behavior.releaseOnMonitorDisconnect) ||
                   (target == .disconnected && ownershipReason == .usbHub && usesUSBHubAutomation && !automaticClaimReady)) {
            scheduleAutomaticRetry(for: target)
        }
    }

    private func beginReconfiguration() {
        guard hasPendingKeyboardConfiguration, !isSleeping else { return }

        if keyboard.state == .connectedLocal {
            guard !reconfigurationReleaseAttempted else {
                failReconfiguration("Unable to release the previous keyboard; the selection was not changed.")
                return
            }

            reconfigurationReleaseAttempted = true
            desiredState = .disconnected
            ownershipReason = .none
            failedDesiredState = nil
            beginOperation(for: .disconnected)
            return
        }

        applyPendingKeyboardConfiguration()
    }

    private func applyPendingKeyboardConfiguration() {
        guard hasPendingKeyboardConfiguration else { return }

        let descriptor = pendingKeyboard
        pendingKeyboard = nil
        hasPendingKeyboardConfiguration = false
        keyboard.configuredKeyboard = descriptor
        keyboard.refreshState()

        if keyboard.state == .connectedLocal {
            desiredState = automaticClaimReady ? .connected : .disconnected
            ownershipReason = usesUSBHubAutomation
                ? .usbHub
                : (automaticClaimReady ? .monitor : .existing)
        } else if automaticClaimReady {
            desiredState = .connected
            ownershipReason = usesUSBHubAutomation ? .usbHub : .monitor
        } else {
            desiredState = .disconnected
            ownershipReason = .none
        }

        failedDesiredState = nil
        lastError = nil
        publish()
        reconcile(force: true)
    }

    private func failReconfiguration(_ message: String) {
        let oldReason = originalOwnershipReason
        hasPendingKeyboardConfiguration = false
        pendingKeyboard = nil
        reconfigurationReleaseAttempted = false
        ownershipReason = oldReason

        if keyboard.state == .connectedLocal {
            if oldReason == .monitor,
               usesMonitorAutomation,
               !monitorPresent,
               behavior.releaseOnMonitorDisconnect {
                desiredState = .disconnected
            } else if oldReason == .usbHub,
                      usesUSBHubAutomation,
                      !automaticClaimReady {
                desiredState = .disconnected
            } else {
                desiredState = .connected
            }
        } else {
            desiredState = .disconnected
            ownershipReason = .none
        }

        failedDesiredState = desiredState
        lastError = message
        publish()
        onKeyboardReconfigurationFailure?(message)

        if desiredState == .disconnected,
           ownershipReason == .monitor,
           usesMonitorAutomation,
           !monitorPresent,
           behavior.releaseOnMonitorDisconnect {
            scheduleAutomaticRetry(for: .disconnected)
        } else if desiredState == .disconnected,
                  ownershipReason == .usbHub,
                  usesUSBHubAutomation,
                  !automaticClaimReady {
            scheduleAutomaticRetry(for: .disconnected)
        }
    }

    private func scheduleAutomaticRetry(for target: DesiredKeyboardState) {
        guard automaticRetryCount < 2,
              automaticRetryTask == nil else {
            return
        }

        automaticRetryCount += 1
        automaticRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }

            guard let self else { return }
            self.automaticRetryTask = nil

            guard !self.operationInProgress else { return }

            switch target {
            case .connected:
                if self.ownershipReason == .monitor {
                    guard self.usesMonitorAutomation,
                          self.monitorPresent,
                          self.behavior.claimOnMonitorConnect,
                          self.desiredState == .connected else {
                        return
                    }
                } else {
                    guard self.ownershipReason == .usbHub,
                          self.usesUSBHubAutomation,
                          self.automaticClaimReady,
                          self.kvmClaimIntent,
                          self.desiredState == .connected else {
                        return
                    }
                }
            case .disconnected:
                let releasesMonitorOwnedKeyboard = self.usesMonitorAutomation && self.ownershipReason == .monitor
                let releasesSelectedUSBKeyboard = self.usesUSBHubAutomation &&
                    self.ownershipReason == .usbHub &&
                    self.keyboard.configuredKeyboard != nil
                guard (!self.monitorPresent || (self.usesUSBHubAutomation && !self.usbHubPresent)),
                      (self.usesUSBHubAutomation || self.behavior.releaseOnMonitorDisconnect),
                      releasesMonitorOwnedKeyboard || releasesSelectedUSBKeyboard,
                      self.desiredState == .disconnected else {
                    return
                }
            }

            guard !self.isSleeping else {
                return
            }

            self.failedDesiredState = nil
            self.reconcile(force: true)
        }
    }

    private func cancelAutomaticRetry() {
        automaticRetryTask?.cancel()
        automaticRetryTask = nil
    }

    private func scheduleUSBHubClaim() {
        guard usbHubClaimTask == nil else { return }

        usbHubClaimTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.usbHubClaimDelayNanoseconds)
            guard !Task.isCancelled else { return }

            guard let self else { return }
            self.usbHubClaimTask = nil
            guard self.usesUSBHubAutomation,
                  self.automaticClaimReady,
                  self.kvmClaimIntent,
                  self.desiredState == .connected,
                  !self.operationInProgress,
                  !self.isSleeping else {
                return
            }

            self.reconcile(force: true)
        }
    }

    private func cancelUSBHubClaim() {
        usbHubClaimTask?.cancel()
        usbHubClaimTask = nil
    }

    private func restoreDisplayAfterKeyboardClaimIfNeeded() {
        guard !operationInProgress,
              !isSleeping,
              keyboard.state == .connectedLocal else {
            return
        }

        displayHandoff?.restoreAfterKeyboardClaim()
        displayHandoffActive = displayHandoff?.hasPendingKeyboardRelease ?? false
    }

    private func publish() {
        snapshot = OwnershipSnapshot(
            keyboardState: keyboard.state,
            ownershipReason: ownershipReason,
            monitorPresent: monitorPresent,
            usbHubPresent: usbHubPresent,
            isBusy: operationInProgress,
            errorMessage: lastError
        )
        onChange?(snapshot)
    }
}
