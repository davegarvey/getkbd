import Foundation

@MainActor
final class OwnershipController {
    private let keyboard: KeyboardControlling

    private(set) var snapshot: OwnershipSnapshot
    private(set) var desiredState: DesiredKeyboardState?

    var onChange: ((OwnershipSnapshot) -> Void)?

    private var behavior: AutomaticBehavior
    private var ownershipReason: OwnershipReason = .none
    private var monitorPresent = false
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

    var onKeyboardReconfigurationFailure: ((String) -> Void)?

    init(keyboard: KeyboardControlling, behavior: AutomaticBehavior) {
        self.keyboard = keyboard
        self.behavior = behavior
        self.snapshot = OwnershipSnapshot(
            keyboardState: keyboard.state,
            ownershipReason: .none,
            monitorPresent: false,
            isBusy: false,
            errorMessage: nil
        )

        keyboard.onStateChange = { [weak self] _ in
            self?.keyboardStateChanged()
        }
    }

    func start(monitorPresent: Bool) {
        self.monitorPresent = monitorPresent
        keyboard.refreshState()

        if keyboard.state == .connectedLocal {
            ownershipReason = monitorPresent && behavior.claimOnMonitorConnect ? .monitor : .existing
            desiredState = .connected
        } else {
            let shouldClaim = monitorPresent && behavior.claimOnMonitorConnect
            ownershipReason = shouldClaim ? .monitor : .none
            desiredState = shouldClaim ? .connected : .disconnected
        }

        failedDesiredState = nil
        lastError = nil
        publish()
        reconcile(force: desiredState == .connected)
    }

    func updateBehavior(_ behavior: AutomaticBehavior, monitorPresent: Bool) {
        self.behavior = behavior
        self.monitorPresent = monitorPresent

        if isSleeping {
            publish()
            return
        }

        if hasPendingKeyboardConfiguration {
            desiredState = monitorPresent && behavior.claimOnMonitorConnect ? .connected : .disconnected
            ownershipReason = desiredState == .connected ? .monitor : .none
            failedDesiredState = nil
            lastError = nil
            publish()
            if !operationInProgress {
                beginReconfiguration()
            }
            return
        }

        keyboard.refreshState()
        if monitorPresent,
           behavior.claimOnMonitorConnect,
           behavior.monitorTakesOwnershipFromManual,
           ownershipReason == .manual {
            ownershipReason = .monitor
        }

        if keyboard.state == .connectedLocal {
            if !monitorPresent,
               behavior.releaseOnMonitorDisconnect,
               ownershipReason == .monitor {
                desiredState = .disconnected
            } else {
                desiredState = .connected
                if ownershipReason == .none {
                    ownershipReason = .existing
                }
            }
        } else if monitorPresent && behavior.claimOnMonitorConnect {
            desiredState = .connected
            if ownershipReason == .none {
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

        guard behavior.claimOnMonitorConnect else {
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
        reconcile(force: true)
    }

    func monitorDisconnected() {
        monitorPresent = false
        cancelAutomaticRetry()
        automaticRetryCount = 0

        guard behavior.releaseOnMonitorDisconnect,
              ownershipReason == .monitor else {
            publish()
            return
        }

        desiredState = .disconnected
        failedDesiredState = nil
        GetKbdLog.event("monitor.disconnected")

        if keyboard.state == .disconnected && !operationInProgress {
            ownershipReason = .none
        }

        publish()
        reconcile(force: true)
    }

    func manualClaim() {
        guard !isSleeping else { return }

        cancelAutomaticRetry()
        automaticRetryCount = 0
        desiredState = .connected
        ownershipReason = .manual
        failedDesiredState = nil
        lastError = nil
        publish()
        reconcile(force: true)
    }

    func manualRelease() {
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
            desiredState = monitorPresent && behavior.claimOnMonitorConnect ? .connected : .disconnected
            ownershipReason = desiredState == .connected ? .monitor : .none
            failedDesiredState = nil
            lastError = nil
            publish()
            if !operationInProgress {
                beginReconfiguration()
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
               behavior.claimOnMonitorConnect,
               behavior.monitorTakesOwnershipFromManual {
                ownershipReason = .monitor
            }

            if ownershipReason == .monitor,
               !monitorPresent,
               behavior.releaseOnMonitorDisconnect {
                desiredState = .disconnected
                failedDesiredState = nil
                publish()
                reconcile(force: true)
            } else {
                desiredState = .connected
                publish()
            }
            return
        }

        sleepOwnershipReason = nil

        guard monitorPresent && behavior.claimOnMonitorConnect else {
            if keyboard.state == .connectedLocal && ownershipReason == .none {
                ownershipReason = .existing
                desiredState = .connected
            }
            publish()
            return
        }

        if keyboard.state == .connectedLocal {
            desiredState = .connected
            if ownershipReason == .none {
                ownershipReason = .existing
            }
            publish()
            return
        }

        desiredState = .connected
        ownershipReason = .monitor
        failedDesiredState = nil
        publish()
        reconcile(force: true)
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
        }

        publish()

        if (keyboard.state == .disconnected || keyboard.state == .failed),
           !operationInProgress {
            if desiredState == .connected,
               ownershipReason == .monitor,
               monitorPresent {
                scheduleAutomaticRetry(for: .connected)
            } else if desiredState == .disconnected,
                      ownershipReason == .monitor,
                      !monitorPresent,
                      behavior.releaseOnMonitorDisconnect {
                scheduleAutomaticRetry(for: .disconnected)
            }
        }
    }

    func reconfigureKeyboard(to descriptor: KeyboardDescriptor?, monitorPresent: Bool) {
        guard keyboard.configuredKeyboard != descriptor || hasPendingKeyboardConfiguration else {
            return
        }

        self.monitorPresent = monitorPresent
        if !hasPendingKeyboardConfiguration {
            originalOwnershipReason = ownershipReason
            reconfigurationReleaseAttempted = false
        }
        pendingKeyboard = descriptor
        hasPendingKeyboardConfiguration = true
        desiredState = monitorPresent && behavior.claimOnMonitorConnect && !isSleeping ? .connected : .disconnected
        ownershipReason = desiredState == .connected ? .monitor : .none
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
        while operationInProgress {
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

            if target == .disconnected, desiredState == .disconnected {
                ownershipReason = .none
            } else if target == .connected,
                      desiredState == .connected,
                      ownershipReason == .none {
                ownershipReason = .existing
            }
        } else {
            failedDesiredState = target
            lastError = keyboard.lastError ?? "Bluetooth operation failed"
        }

        publish()

        if desiredState != target {
            failedDesiredState = nil
            reconcile(force: true)
        } else if !succeeded,
                  ((target == .connected && ownershipReason == .monitor && monitorPresent) ||
                   (target == .disconnected && ownershipReason == .monitor && !monitorPresent && behavior.releaseOnMonitorDisconnect)) {
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
            desiredState = .connected
            ownershipReason = monitorPresent && behavior.claimOnMonitorConnect ? .monitor : .existing
        } else if monitorPresent && behavior.claimOnMonitorConnect {
            desiredState = .connected
            ownershipReason = .monitor
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
               !monitorPresent,
               behavior.releaseOnMonitorDisconnect {
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
           !monitorPresent,
           behavior.releaseOnMonitorDisconnect {
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
                guard self.monitorPresent,
                      self.behavior.claimOnMonitorConnect,
                      self.ownershipReason == .monitor,
                      self.desiredState == .connected else {
                    return
                }
            case .disconnected:
                guard !self.monitorPresent,
                      self.behavior.releaseOnMonitorDisconnect,
                      self.ownershipReason == .monitor,
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

    private func publish() {
        snapshot = OwnershipSnapshot(
            keyboardState: keyboard.state,
            ownershipReason: ownershipReason,
            monitorPresent: monitorPresent,
            isBusy: operationInProgress,
            errorMessage: lastError
        )
        onChange?(snapshot)
    }
}
