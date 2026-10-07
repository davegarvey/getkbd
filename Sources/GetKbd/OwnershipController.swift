import Foundation

struct AutomaticClaimRetryPolicy: Sendable {
    let fastRecoveryWindowNanoseconds: UInt64
    let minimumStartIntervalNanoseconds: UInt64
    let slowRetryDelaysNanoseconds: [UInt64]
    let releaseRetryDelaysNanoseconds: [UInt64]

    static let standard = AutomaticClaimRetryPolicy(
        fastRecoveryWindowNanoseconds: 120_000_000_000,
        minimumStartIntervalNanoseconds: 5_000_000_000,
        slowRetryDelaysNanoseconds: [15_000_000_000, 30_000_000_000, 60_000_000_000],
        releaseRetryDelaysNanoseconds: [1_000_000_000, 1_000_000_000]
    )
}

@MainActor
final class OwnershipController {
    private let keyboard: KeyboardControlling

    private(set) var snapshot: OwnershipSnapshot
    private(set) var desiredState: DesiredKeyboardState?

    var onChange: ((OwnershipSnapshot) -> Void)?
    var onKeyboardReconfigurationFailure: ((String) -> Void)?

    private var monitorPresent = false
    private var usbHubPresent = false
    private var isSleeping = false
    private var manualTarget: DesiredKeyboardState?
    private var operationInProgress = false
    private var operationTarget: DesiredKeyboardState?
    private var restartClaimRequested = false
    private var failedDesiredState: DesiredKeyboardState?
    private var lastError: String?
    private var automaticRetryTask: Task<Void, Never>?
    private var automaticRetryCount = 0
    private var automaticClaimCycleStartedAtNanoseconds: UInt64?
    private var lastAutomaticClaimStartedAtNanoseconds: UInt64?
    private var automaticClaimSlowRetryCount = 0
    private var automaticReleaseRetryCount = 0
    private var usbHubClaimTask: Task<Void, Never>?
    private var pendingKeyboard: KeyboardDescriptor?
    private var hasPendingKeyboardConfiguration = false
    private var reconfigurationReleaseAttempted = false

    private static let usbHubClaimDelayNanoseconds: UInt64 = 750_000_000
    private let claimRetryPolicy: AutomaticClaimRetryPolicy

    private var automaticClaimReady: Bool {
        !isSleeping && monitorPresent && usbHubPresent
    }

    init(
        keyboard: KeyboardControlling,
        claimRetryPolicy: AutomaticClaimRetryPolicy = .standard
    ) {
        self.keyboard = keyboard
        self.claimRetryPolicy = claimRetryPolicy
        snapshot = OwnershipSnapshot(
            keyboardState: keyboard.state,
            ownershipReason: .none,
            monitorPresent: false,
            usbHubPresent: false,
            isBusy: false,
            errorMessage: nil,
            bluetoothAvailability: keyboard.bluetoothAvailability
        )

        keyboard.onBluetoothAvailabilityChange = { [weak self] in
            guard let self else { return }
            self.resetAutomaticAttempts()
            self.updateIntent()
            self.publish()
            self.reconcile(force: true, immediate: false)
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
        guard !isSleeping, keyboard.bluetoothAvailability == .poweredOn else { return }
        manualTarget = .connected
        resetAutomaticAttempts()
        updateIntent()
        publish()
        reconcile(force: true, immediate: true)
    }

    func manualRelease() {
        guard keyboard.bluetoothAvailability == .poweredOn else { return }
        manualTarget = .disconnected
        resetAutomaticAttempts()
        updateIntent()
        publish()
        reconcile(force: true, immediate: true)
    }

    /// Starts a claim at once, stopping one that is still waiting for the keyboard to pair.
    /// The current automatic or manual target is kept.
    func connectNow() {
        guard !isSleeping,
              !hasPendingKeyboardConfiguration,
              desiredState == .connected,
              keyboard.state != .connectedLocal else {
            return
        }

        GetKbdLog.event("keyboard.claim.now")
        cancelAutomaticAttempts()
        failedDesiredState = nil
        lastError = nil

        if operationInProgress {
            guard operationTarget == .connected else { return }
            restartClaimRequested = true
            keyboard.cancelConnect()
            publish()
        } else {
            publish()
            reconcile(force: true, immediate: true)
        }
    }

    func willSleep() {
        isSleeping = true
        manualTarget = nil
        cancelAutomaticAttempts()
        desiredState = .disconnected
        ownershipReason = .none
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

    func keyboardStateChanged() {
        publish()
        guard !operationInProgress,
              !hasPendingKeyboardConfiguration else {
            return
        }

        if keyboard.state == .connectedLocal {
            failedDesiredState = nil
            cancelAutomaticRetry()
            resetRetryTracking()
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
            beginOperation(for: .disconnected)
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
        guard !operationInProgress, keyboard.bluetoothAvailability == .poweredOn else { return }

        if !hasPendingKeyboardConfiguration {
            updateIntent()
        }
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
                beginOperation(for: .connected)
            } else {
                scheduleUSBHubClaim()
            }

        case .disconnected:
            cancelUSBHubClaim()
            guard keyboard.state == .connectedLocal else { return }
            guard force || failedDesiredState != .disconnected else { return }
            beginOperation(for: .disconnected)
        }
    }

    private func beginOperation(for target: DesiredKeyboardState) {
        guard !operationInProgress, keyboard.bluetoothAvailability == .poweredOn else { return }

        if target == .connected, manualTarget == nil {
            let now = DispatchTime.now().uptimeNanoseconds
            automaticClaimCycleStartedAtNanoseconds = automaticClaimCycleStartedAtNanoseconds ?? now
            lastAutomaticClaimStartedAtNanoseconds = now
        }

        operationInProgress = true
        operationTarget = target
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
        let restartClaim = restartClaimRequested && target == .connected
        restartClaimRequested = false

        // Refresh while still busy so that the state change does not reconcile before the
        // outcome below is recorded.
        keyboard.refreshState()
        operationInProgress = false
        operationTarget = nil

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
                beginOperation(for: .disconnected)
            } else {
                applyPendingKeyboardConfiguration()
            }
            return
        }

        if succeeded {
            failedDesiredState = nil
            lastError = nil
            cancelAutomaticRetry()
            resetRetryTracking()
            if target == .connected {
                cancelUSBHubClaim()
            }
            updateIntent()
        } else if restartClaim {
            failedDesiredState = nil
            lastError = nil
        } else {
            failedDesiredState = target
            lastError = keyboard.lastError ?? "Bluetooth operation failed"
        }

        if desiredState != target {
            failedDesiredState = nil
            publish()
            reconcile(force: true, immediate: desiredState == .connected && manualTarget != nil)
        } else if !succeeded, restartClaim {
            publish()
            reconcile(force: true, immediate: true)
        } else {
            if !succeeded, manualTarget == nil {
                scheduleAutomaticRetry(for: target)
            }
            publish()
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
        guard keyboard.bluetoothAvailability == .poweredOn,
              manualTarget == nil,
              automaticRetryTask == nil else {
            return
        }

        let delay: UInt64
        if target == .connected {
            let now = DispatchTime.now().uptimeNanoseconds
            let cycleStartedAt = automaticClaimCycleStartedAtNanoseconds ?? now
            automaticClaimCycleStartedAtNanoseconds = cycleStartedAt

            if now - cycleStartedAt < claimRetryPolicy.fastRecoveryWindowNanoseconds {
                let lastStartedAt = lastAutomaticClaimStartedAtNanoseconds ?? now
                let earliestNextStart = lastStartedAt &+ claimRetryPolicy.minimumStartIntervalNanoseconds
                delay = now >= earliestNextStart ? 0 : earliestNextStart - now
            } else {
                guard automaticClaimSlowRetryCount < claimRetryPolicy.slowRetryDelaysNanoseconds.count else {
                    return
                }
                delay = claimRetryPolicy.slowRetryDelaysNanoseconds[automaticClaimSlowRetryCount]
                automaticClaimSlowRetryCount += 1
            }
        } else {
            guard automaticReleaseRetryCount < claimRetryPolicy.releaseRetryDelaysNanoseconds.count else {
                return
            }
            delay = claimRetryPolicy.releaseRetryDelaysNanoseconds[automaticReleaseRetryCount]
            automaticReleaseRetryCount += 1
        }

        automaticRetryCount += 1
        automaticRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }

            guard let self else { return }
            self.automaticRetryTask = nil
            guard !self.isSleeping,
                  !self.operationInProgress,
                  self.manualTarget == nil,
                  self.desiredState == target,
                  target == .connected ? self.automaticClaimReady : !self.automaticClaimReady else {
                self.publish()
                return
            }

            self.failedDesiredState = nil
            self.reconcile(force: true, immediate: true)
        }
    }

    private func cancelAutomaticAttempts() {
        cancelUSBHubClaim()
        cancelAutomaticRetry()
        resetRetryTracking()
    }

    private func resetRetryTracking() {
        automaticRetryCount = 0
        automaticClaimCycleStartedAtNanoseconds = nil
        lastAutomaticClaimStartedAtNanoseconds = nil
        automaticClaimSlowRetryCount = 0
        automaticReleaseRetryCount = 0
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

    private var isRetryingClaim: Bool {
        desiredState == .connected &&
            keyboard.state != .connectedLocal &&
            automaticRetryCount > 0 &&
            (automaticRetryTask != nil || operationTarget == .connected)
    }

    private func publish() {
        snapshot = OwnershipSnapshot(
            keyboardState: keyboard.state,
            ownershipReason: ownershipReason,
            monitorPresent: monitorPresent,
            usbHubPresent: usbHubPresent,
            isBusy: operationInProgress,
            errorMessage: lastError,
            bluetoothAvailability: keyboard.bluetoothAvailability,
            isRetryingClaim: isRetryingClaim
        )
        onChange?(snapshot)
    }
}
