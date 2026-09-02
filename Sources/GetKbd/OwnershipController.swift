import Foundation

@MainActor
final class OwnershipController {
    private let keyboard: KeyboardControlling
    private let display: DisplayParkingControlling?

    private(set) var snapshot: OwnershipSnapshot
    private(set) var desiredState: DesiredKeyboardState?

    var onChange: ((OwnershipSnapshot) -> Void)?
    var onKeyboardReconfigurationFailure: ((String) -> Void)?

    private var monitorPresent = false
    private var usbHubPresent = false
    private var isSleeping = false
    private var manualTarget: DesiredKeyboardState?
    private var operationInProgress = false
    private var failedDesiredState: DesiredKeyboardState?
    private var lastError: String?
    private var automaticRetryTask: Task<Void, Never>?
    private var automaticRetryCount = 0
    private var usbHubClaimTask: Task<Void, Never>?
    private var pendingKeyboard: KeyboardDescriptor?
    private var hasPendingKeyboardConfiguration = false
    private var reconfigurationReleaseAttempted = false

    private static let usbHubClaimDelayNanoseconds: UInt64 = 750_000_000
    private static let automaticRetryDelayNanoseconds: UInt64 = 1_000_000_000

    private var automaticClaimReady: Bool {
        !isSleeping && monitorPresent && usbHubPresent
    }

    private var displayShouldBeRestored: Bool {
        if let manualTarget {
            return manualTarget == .connected
        }
        return automaticClaimReady
    }

    init(
        keyboard: KeyboardControlling,
        display: DisplayParkingControlling? = nil
    ) {
        self.keyboard = keyboard
        self.display = display
        snapshot = OwnershipSnapshot(
            keyboardState: keyboard.state,
            ownershipReason: .none,
            monitorPresent: false,
            usbHubPresent: false,
            isBusy: false,
            errorMessage: nil
        )

        display?.onStateChange = { [weak self] in
            self?.publish()
        }
        keyboard.onStateChange = { [weak self] _ in
            self?.keyboardStateChanged()
        }
    }

    func start(monitorPresent: Bool, usbHubPresent: Bool = false) {
        self.monitorPresent = monitorPresent
        self.usbHubPresent = usbHubPresent
        manualTarget = nil
        resetAutomaticAttempts()
        keyboard.refreshState()
        updateIntent()
        publish()
        reconcile(force: true, immediate: false)
    }

    func updateSignals(monitorPresent: Bool, usbHubPresent: Bool) {
        self.monitorPresent = monitorPresent
        self.usbHubPresent = usbHubPresent
        manualTarget = nil
        resetAutomaticAttempts()
        guard !isSleeping else {
            publish()
            return
        }

        keyboard.refreshState()
        updateIntent()
        publish()
        reconcile(force: true, immediate: false)
    }

    func monitorConnected() {
        monitorPresent = true
        sensorChanged(logEvent: "monitor.connected")
    }

    func monitorDisconnected() {
        monitorPresent = false
        sensorChanged(logEvent: "monitor.disconnected")
    }

    func usbHubConnected() {
        usbHubPresent = true
        sensorChanged(logEvent: "usb.hub.connected")
    }

    func usbHubDisconnected() {
        usbHubPresent = false
        sensorChanged(logEvent: "usb.hub.disconnected")
    }

    func manualClaim() {
        guard !isSleeping else { return }
        manualTarget = .connected
        resetAutomaticAttempts()
        updateIntent()
        publish()
        reconcile(force: true, immediate: true)
    }

    func manualRelease() {
        manualTarget = .disconnected
        resetAutomaticAttempts()
        updateIntent()
        publish()
        reconcile(force: true, immediate: true)
    }

    func willSleep() {
        isSleeping = true
        manualTarget = nil
        cancelAutomaticAttempts()
        desiredState = .disconnected
        ownershipReason = .none
        syncDisplay()
        publish()
        reconcile(force: true, immediate: true)
    }

    func didWake(monitorPresent: Bool, usbHubPresent: Bool) {
        isSleeping = false
        self.monitorPresent = monitorPresent
        self.usbHubPresent = usbHubPresent
        manualTarget = nil
        resetAutomaticAttempts()
        keyboard.refreshState()
        updateIntent()
        publish()
        reconcile(force: true, immediate: false)
    }

    func displayStateChanged() {
        publish()
    }

    func retryDisplayParking() {
        syncDisplay()
        publish()
    }

    func keyboardStateChanged() {
        publish()
        guard !operationInProgress,
              !hasPendingKeyboardConfiguration else {
            return
        }

        if keyboard.state == .connectedLocal {
            failedDesiredState = nil
            automaticRetryCount = 0
            cancelAutomaticRetry()
        }

        reconcile(force: false, immediate: false)
    }

    func reconfigureKeyboard(to descriptor: KeyboardDescriptor?) {
        guard keyboard.configuredKeyboard != descriptor || hasPendingKeyboardConfiguration else {
            return
        }

        pendingKeyboard = descriptor
        hasPendingKeyboardConfiguration = true
        reconfigurationReleaseAttempted = false
        cancelAutomaticAttempts()

        if !operationInProgress, keyboard.state == .connectedLocal {
            desiredState = .disconnected
            ownershipReason = .none
            failedDesiredState = nil
            lastError = nil
            publish()
            beginOperation(for: .disconnected, syncDisplay: false)
        } else if !operationInProgress {
            applyPendingKeyboardConfiguration()
        }
    }

    func waitForIdle() async {
        while operationInProgress || usbHubClaimTask != nil || automaticRetryTask != nil {
            await Task.yield()
        }
    }

    private var ownershipReason: OwnershipReason = .none

    private func sensorChanged(logEvent: String) {
        manualTarget = nil
        resetAutomaticAttempts()
        GetKbdLog.event(logEvent)
        updateIntent()
        publish()
        reconcile(force: true, immediate: false)
    }

    private func updateIntent() {
        if let manualTarget {
            desiredState = manualTarget
            ownershipReason = .manual
            return
        }

        desiredState = automaticClaimReady ? .connected : .disconnected
        if automaticClaimReady || keyboard.state == .connectedLocal {
            ownershipReason = .usbHub
        } else {
            ownershipReason = .none
        }
    }

    private func reconcile(force: Bool, immediate: Bool) {
        guard !operationInProgress else { return }

        if !hasPendingKeyboardConfiguration {
            updateIntent()
        }
        syncDisplay()

        guard let desiredState else { return }

        switch desiredState {
        case .connected:
            guard keyboard.configuredKeyboard != nil,
                  keyboard.state != .connectedLocal,
                  keyboard.state != .connecting,
                  keyboard.state != .disconnecting else {
                return
            }
            guard force || failedDesiredState != .connected else { return }

            if immediate || manualTarget != nil {
                beginOperation(for: .connected, syncDisplay: false)
            } else {
                scheduleUSBHubClaim()
            }

        case .disconnected:
            cancelUSBHubClaim()
            guard keyboard.state == .connectedLocal else { return }
            guard force || failedDesiredState != .disconnected else { return }
            beginOperation(for: .disconnected, syncDisplay: false)
        }
    }

    private func beginOperation(for target: DesiredKeyboardState, syncDisplay: Bool) {
        guard !operationInProgress else { return }

        if syncDisplay {
            self.syncDisplay()
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
        keyboard.refreshState()

        if hasPendingKeyboardConfiguration {
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
                beginOperation(for: .disconnected, syncDisplay: false)
            } else {
                applyPendingKeyboardConfiguration()
            }
            return
        }

        if succeeded {
            failedDesiredState = nil
            lastError = nil
            if target == .connected {
                cancelUSBHubClaim()
            }
            updateIntent()
        } else {
            failedDesiredState = target
            lastError = keyboard.lastError ?? "Bluetooth operation failed"
        }

        publish()

        if desiredState != target {
            failedDesiredState = nil
            reconcile(force: true, immediate: desiredState == .connected && manualTarget != nil)
        } else if !succeeded, manualTarget == nil {
            scheduleAutomaticRetry(for: target)
        }
    }

    private func applyPendingKeyboardConfiguration() {
        guard hasPendingKeyboardConfiguration else { return }

        let descriptor = pendingKeyboard
        pendingKeyboard = nil
        hasPendingKeyboardConfiguration = false
        reconfigurationReleaseAttempted = false
        keyboard.configuredKeyboard = descriptor
        keyboard.refreshState()
        failedDesiredState = nil
        lastError = nil
        updateIntent()
        publish()
        reconcile(force: true, immediate: manualTarget != nil)
    }

    private func failReconfiguration(_ message: String) {
        hasPendingKeyboardConfiguration = false
        pendingKeyboard = nil
        reconfigurationReleaseAttempted = false
        lastError = message
        updateIntent()
        publish()
        onKeyboardReconfigurationFailure?(message)
    }

    private func syncDisplay() {
        if isSleeping {
            display?.park()
            return
        }

        if displayShouldBeRestored {
            display?.restore()
        } else {
            display?.park()
        }
    }

    private func scheduleUSBHubClaim() {
        guard usbHubClaimTask == nil,
              manualTarget == nil,
              automaticClaimReady else {
            return
        }

        usbHubClaimTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.usbHubClaimDelayNanoseconds)
            guard !Task.isCancelled else { return }

            guard let self else { return }
            self.usbHubClaimTask = nil
            guard self.manualTarget == nil,
                  self.automaticClaimReady,
                  self.desiredState == .connected,
                  !self.operationInProgress else {
                return
            }

            self.reconcile(force: true, immediate: true)
        }
    }

    private func scheduleAutomaticRetry(for target: DesiredKeyboardState) {
        guard manualTarget == nil,
              automaticRetryCount < 2,
              automaticRetryTask == nil else {
            return
        }

        automaticRetryCount += 1
        automaticRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.automaticRetryDelayNanoseconds)
            guard !Task.isCancelled else { return }

            guard let self else { return }
            self.automaticRetryTask = nil
            guard !self.isSleeping,
                  !self.operationInProgress,
                  self.manualTarget == nil,
                  self.desiredState == target,
                  target == .connected ? self.automaticClaimReady : !self.automaticClaimReady else {
                return
            }

            self.failedDesiredState = nil
            self.reconcile(force: true, immediate: true)
        }
    }

    private func cancelAutomaticAttempts() {
        cancelUSBHubClaim()
        cancelAutomaticRetry()
        automaticRetryCount = 0
    }

    private func resetAutomaticAttempts() {
        cancelAutomaticAttempts()
        failedDesiredState = nil
        lastError = nil
    }

    private func cancelUSBHubClaim() {
        usbHubClaimTask?.cancel()
        usbHubClaimTask = nil
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
            usbHubPresent: usbHubPresent,
            isBusy: operationInProgress,
            errorMessage: lastError,
            displayParkingState: display?.parkingState ?? .idle,
            displayParkingError: display?.parkingError
        )
        onChange?(snapshot)
    }
}
