import XCTest
@testable import GetKbd

@MainActor
final class OwnershipControllerTests: XCTestCase {
    func testBluetoothOffBlocksAutomaticAndManualActionsThenRecovers() async {
        let keyboard = FakeKeyboardController()
        keyboard.bluetoothAvailability = .poweredOff
        let controller = OwnershipController(keyboard: keyboard)
        controller.start(monitorPresent: true, usbHubPresent: true)
        controller.manualClaim()
        controller.manualRelease()
        await controller.waitForIdle()
        XCTAssertEqual(keyboard.connectCallCount, 0)
        XCTAssertEqual(keyboard.disconnectCallCount, 0)
        XCTAssertEqual(controller.snapshot.bluetoothAvailability, .poweredOff)

        keyboard.bluetoothAvailability = .poweredOn
        keyboard.onBluetoothAvailabilityChange?()
        await controller.waitForIdle()
        XCTAssertEqual(keyboard.connectCallCount, 1)
        XCTAssertEqual(controller.snapshot.keyboardState, .connectedLocal)
    }

    func testBluetoothOffCancelsPendingClaimAndRecoveryRespectsHub() async {
        let keyboard = FakeKeyboardController()
        let controller = OwnershipController(keyboard: keyboard)
        controller.start(monitorPresent: true, usbHubPresent: true)
        keyboard.bluetoothAvailability = .poweredOff
        keyboard.onBluetoothAvailabilityChange?()
        await controller.waitForIdle()
        XCTAssertEqual(keyboard.connectCallCount, 0)
        controller.usbHubDisconnected()
        keyboard.bluetoothAvailability = .poweredOn
        keyboard.onBluetoothAvailabilityChange?()
        await controller.waitForIdle()
        XCTAssertEqual(keyboard.connectCallCount, 0)
    }

    func testPowerLossDuringClaimDoesNotRetryUntilRestored() async {
        let keyboard = FakeKeyboardController()
        keyboard.blockNextConnect = true
        let controller = OwnershipController(keyboard: keyboard)
        controller.start(monitorPresent: true, usbHubPresent: true)
        await keyboard.waitUntilConnectIsBlocked()
        keyboard.bluetoothAvailability = .poweredOff
        keyboard.onBluetoothAvailabilityChange?()
        keyboard.completeBlockedConnect(success: false)
        await controller.waitForIdle()
        XCTAssertEqual(keyboard.connectCallCount, 1)
        XCTAssertEqual(controller.snapshot.bluetoothAvailability, .poweredOff)
        keyboard.bluetoothAvailability = .poweredOn
        keyboard.onBluetoothAvailabilityChange?()
        await controller.waitForIdle()
        XCTAssertEqual(keyboard.connectCallCount, 2)
    }

    func testInactiveStartupDoesNotClaimKeyboard() async {
        let keyboard = FakeKeyboardController()
        let controller = OwnershipController(keyboard: keyboard)

        controller.start(monitorPresent: true, usbHubPresent: false)
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.connectCallCount, 0)
        XCTAssertEqual(keyboard.disconnectCallCount, 0)
        XCTAssertTrue(controller.snapshot.monitorPresent)
    }

    func testHubPresenceClaimsKeyboard() async {
        let keyboard = FakeKeyboardController()
        let controller = OwnershipController(keyboard: keyboard)

        controller.start(monitorPresent: true, usbHubPresent: false)
        controller.usbHubConnected()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.connectCallCount, 1)
        XCTAssertEqual(controller.snapshot.keyboardState, .connectedLocal)
        XCTAssertEqual(controller.snapshot.ownershipReason, .usbHub)
    }

    func testHubLossReleasesKeyboardWithoutChangingDisplay() async {
        let keyboard = FakeKeyboardController()
        keyboard.currentState = .connectedLocal
        let controller = OwnershipController(keyboard: keyboard)

        controller.start(monitorPresent: true, usbHubPresent: true)
        await controller.waitForIdle()

        controller.usbHubDisconnected()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.disconnectCallCount, 1)
        XCTAssertEqual(controller.snapshot.keyboardState, .disconnected)
        XCTAssertEqual(controller.snapshot.ownershipReason, .none)
    }

    func testMissingMonitorIsAClaimSafetyCondition() async {
        let keyboard = FakeKeyboardController()
        let controller = OwnershipController(keyboard: keyboard)

        controller.start(monitorPresent: false, usbHubPresent: true)
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.connectCallCount, 0)
        XCTAssertEqual(controller.snapshot.keyboardState, .disconnected)
    }

    func testManualClaimWorksWithoutAutomaticSignalAndLeavesDisplayAlone() async {
        let keyboard = FakeKeyboardController()
        let controller = OwnershipController(keyboard: keyboard)

        controller.start(monitorPresent: false, usbHubPresent: false)
        controller.manualClaim()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.connectCallCount, 1)
        XCTAssertEqual(controller.snapshot.keyboardState, .connectedLocal)
        XCTAssertEqual(controller.snapshot.ownershipReason, .manual)
    }

    func testSleepReleasesKeyboardWithoutChangingDisplay() async {
        let keyboard = FakeKeyboardController()
        keyboard.currentState = .connectedLocal
        let controller = OwnershipController(keyboard: keyboard)

        controller.start(monitorPresent: true, usbHubPresent: true)
        await controller.waitForIdle()

        controller.willSleep()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.disconnectCallCount, 1)
        XCTAssertEqual(controller.snapshot.keyboardState, .disconnected)
    }

    func testSignalReversalDuringClaimIsReconciledAfterClaimCompletes() async {
        let keyboard = FakeKeyboardController()
        keyboard.blockNextConnect = true
        let controller = OwnershipController(keyboard: keyboard)

        controller.start(monitorPresent: true, usbHubPresent: true)
        await keyboard.waitUntilConnectIsBlocked()
        controller.usbHubDisconnected()

        keyboard.completeBlockedConnect(success: true)
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.connectCallCount, 1)
        XCTAssertEqual(keyboard.disconnectCallCount, 1)
        XCTAssertEqual(controller.snapshot.keyboardState, .disconnected)
    }

    func testFailedAutomaticClaimWaitsForItsScheduledRetry() async throws {
        let keyboard = FakeKeyboardController()
        keyboard.failNextConnects = 1
        let controller = OwnershipController(
            keyboard: keyboard,
            claimRetryPolicy: retryPolicy(fastWindow: 0, slowDelays: [60_000_000_000])
        )

        controller.start(monitorPresent: true, usbHubPresent: true)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        XCTAssertEqual(keyboard.connectCallCount, 1)
        XCTAssertTrue(controller.snapshot.isRetryingClaim)
        XCTAssertFalse(controller.snapshot.isBusy)
    }

    func testRetryLoopEndsAfterLastRetry() async {
        let keyboard = FakeKeyboardController()
        keyboard.failNextConnects = 2
        let controller = OwnershipController(
            keyboard: keyboard,
            claimRetryPolicy: retryPolicy(fastWindow: 0, slowDelays: [0])
        )

        controller.start(monitorPresent: true, usbHubPresent: true)
        await keyboard.waitUntilConnectCount(2)
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.connectCallCount, 2)
        XCTAssertFalse(controller.snapshot.isRetryingClaim)
        XCTAssertEqual(controller.snapshot.keyboardState, .disconnected)
    }

    func testTryNowClaimsImmediatelyWhileRetryIsPending() async throws {
        let keyboard = FakeKeyboardController()
        keyboard.failNextConnects = 1
        let controller = OwnershipController(
            keyboard: keyboard,
            claimRetryPolicy: retryPolicy(fastWindow: 0, slowDelays: [60_000_000_000])
        )

        controller.start(monitorPresent: true, usbHubPresent: true)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertTrue(controller.snapshot.isRetryingClaim)

        controller.connectNow()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.connectCallCount, 2)
        XCTAssertEqual(controller.snapshot.keyboardState, .connectedLocal)
        XCTAssertEqual(controller.snapshot.ownershipReason, .usbHub)
        XCTAssertFalse(controller.snapshot.isRetryingClaim)
    }

    func testTryNowStopsClaimInProgressAndStartsAnother() async {
        let keyboard = FakeKeyboardController()
        keyboard.blockNextConnect = true
        let controller = OwnershipController(keyboard: keyboard)

        controller.start(monitorPresent: true, usbHubPresent: true)
        await keyboard.waitUntilConnectIsBlocked()
        controller.connectNow()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.cancelConnectCallCount, 1)
        XCTAssertEqual(keyboard.connectCallCount, 2)
        XCTAssertEqual(controller.snapshot.keyboardState, .connectedLocal)
        XCTAssertNil(controller.snapshot.errorMessage)
    }

    func testFailedTryNowRestartsTheFastRecoveryWindow() async {
        let keyboard = FakeKeyboardController()
        keyboard.blockNextConnect = true
        keyboard.failNextConnects = 1
        let controller = OwnershipController(
            keyboard: keyboard,
            claimRetryPolicy: retryPolicy(fastWindow: 1_000_000_000, minimumInterval: 100_000_000)
        )

        controller.start(monitorPresent: true, usbHubPresent: true)
        await keyboard.waitUntilConnectIsBlocked()
        controller.connectNow()
        await keyboard.waitUntilConnectCount(3)
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.connectCallCount, 3)
        XCTAssertEqual(controller.snapshot.keyboardState, .connectedLocal)
        XCTAssertEqual(keyboard.maximumConcurrentConnectCount, 1)
    }

    func testFastRecoveryRetriesWithoutAdditionalDelayAfterOrdinaryFailure() async {
        let keyboard = FakeKeyboardController()
        keyboard.failNextConnects = 3
        keyboard.connectDelayNanoseconds = 40_000_000
        let policy = retryPolicy(fastWindow: 300_000_000, minimumInterval: 20_000_000)
        let controller = OwnershipController(keyboard: keyboard, claimRetryPolicy: policy)

        controller.start(monitorPresent: true, usbHubPresent: true)
        await keyboard.waitUntilConnectCount(4)
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.connectCallCount, 4)
        XCTAssertEqual(keyboard.maximumConcurrentConnectCount, 1)
        XCTAssertLessThan(keyboard.connectStartTimes[1] - keyboard.connectStartTimes[0], 100_000_000)
        XCTAssertEqual(controller.snapshot.keyboardState, .connectedLocal)
    }

    func testFastRecoveryEnforcesMinimumIntervalForImmediateFailures() async {
        let keyboard = FakeKeyboardController()
        keyboard.failNextConnects = 1
        let policy = retryPolicy(fastWindow: 1_000_000_000, minimumInterval: 100_000_000)
        let controller = OwnershipController(keyboard: keyboard, claimRetryPolicy: policy)

        controller.start(monitorPresent: true, usbHubPresent: true)
        await keyboard.waitUntilConnectCount(1)
        try? await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(keyboard.connectCallCount, 1)

        await keyboard.waitUntilConnectCount(2)
        await controller.waitForIdle()

        XCTAssertGreaterThanOrEqual(keyboard.connectStartTimes[1] - keyboard.connectStartTimes[0], 100_000_000)
    }

    func testAutomaticClaimsUseSlowBackoffAndStopAfterFinalRetry() async {
        let keyboard = FakeKeyboardController()
        keyboard.failNextConnects = 4
        keyboard.connectDelayNanoseconds = 10_000_000
        let policy = retryPolicy(
            fastWindow: 0,
            slowDelays: [40_000_000, 80_000_000, 120_000_000]
        )
        let controller = OwnershipController(keyboard: keyboard, claimRetryPolicy: policy)

        controller.start(monitorPresent: true, usbHubPresent: true)
        await keyboard.waitUntilConnectCount(4)
        await controller.waitForIdle()
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(keyboard.connectCallCount, 4)
        XCTAssertGreaterThanOrEqual(keyboard.connectStartTimes[1] - keyboard.connectStartTimes[0], 40_000_000)
        XCTAssertGreaterThanOrEqual(keyboard.connectStartTimes[2] - keyboard.connectStartTimes[1], 80_000_000)
        XCTAssertGreaterThanOrEqual(keyboard.connectStartTimes[3] - keyboard.connectStartTimes[2], 120_000_000)
        XCTAssertFalse(controller.snapshot.isRetryingClaim)
    }

    func testSignalTransitionStartsANewFastRetryCycle() async {
        let keyboard = FakeKeyboardController()
        keyboard.failNextConnects = 1
        let controller = OwnershipController(
            keyboard: keyboard,
            claimRetryPolicy: retryPolicy(fastWindow: 0, slowDelays: [60_000_000_000])
        )

        controller.start(monitorPresent: true, usbHubPresent: true)
        await keyboard.waitUntilConnectCount(1)
        while !controller.snapshot.isRetryingClaim {
            await Task.yield()
        }

        controller.usbHubDisconnected()
        controller.usbHubConnected()
        await keyboard.waitUntilConnectCount(2)
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.connectCallCount, 2)
        XCTAssertEqual(controller.snapshot.keyboardState, .connectedLocal)
    }

    func testWakeStartsANewFastRetryCycle() async {
        let keyboard = FakeKeyboardController()
        keyboard.failNextConnects = 1
        let controller = OwnershipController(
            keyboard: keyboard,
            claimRetryPolicy: retryPolicy(fastWindow: 0, slowDelays: [60_000_000_000])
        )

        controller.start(monitorPresent: true, usbHubPresent: true)
        await keyboard.waitUntilConnectCount(1)
        while !controller.snapshot.isRetryingClaim {
            await Task.yield()
        }

        controller.didWake(monitorPresent: true, usbHubPresent: true)
        await keyboard.waitUntilConnectCount(2)
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.connectCallCount, 2)
        XCTAssertEqual(controller.snapshot.keyboardState, .connectedLocal)
    }

    func testAutomaticReleaseRetriesRemainUnchanged() async {
        let keyboard = FakeKeyboardController()
        keyboard.currentState = .connectedLocal
        keyboard.failNextDisconnects = 1
        let controller = OwnershipController(
            keyboard: keyboard,
            claimRetryPolicy: retryPolicy(fastWindow: 0, releaseDelays: [0])
        )

        controller.start(monitorPresent: true, usbHubPresent: true)
        controller.usbHubDisconnected()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.disconnectCallCount, 2)
        XCTAssertEqual(controller.snapshot.keyboardState, .disconnected)
    }

    func testTryNowDoesNothingWhenReleasing() async {
        let keyboard = FakeKeyboardController()
        keyboard.currentState = .connectedLocal
        let controller = OwnershipController(keyboard: keyboard)

        controller.start(monitorPresent: true, usbHubPresent: false)
        controller.connectNow()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.connectCallCount, 0)
        XCTAssertEqual(keyboard.cancelConnectCallCount, 0)
        XCTAssertEqual(controller.snapshot.keyboardState, .disconnected)
    }

    private func retryPolicy(
        fastWindow: UInt64,
        minimumInterval: UInt64 = 0,
        slowDelays: [UInt64] = [],
        releaseDelays: [UInt64] = [1_000_000_000, 1_000_000_000]
    ) -> AutomaticClaimRetryPolicy {
        AutomaticClaimRetryPolicy(
            fastRecoveryWindowNanoseconds: fastWindow,
            minimumStartIntervalNanoseconds: minimumInterval,
            slowRetryDelaysNanoseconds: slowDelays,
            releaseRetryDelaysNanoseconds: releaseDelays
        )
    }
}

@MainActor
private final class FakeKeyboardController: KeyboardControlling {
    var configuredKeyboard: KeyboardDescriptor? = KeyboardDescriptor(
        identifier: "keyboard",
        name: "Shared Keyboard"
    )
    var bluetoothAvailability: BluetoothAvailability = .poweredOn
    var onBluetoothAvailabilityChange: (() -> Void)?
    var currentState: KeyboardConnectionState = .disconnected
    var lastError: String?
    var onStateChange: ((KeyboardConnectionState) -> Void)?
    var connectCallCount = 0
    var disconnectCallCount = 0
    var maximumConcurrentConnectCount = 0
    var connectStartTimes: [UInt64] = []
    var connectDelayNanoseconds: UInt64 = 0
    var blockNextConnect = false
    var failNextConnects = 0
    var failNextDisconnects = 0
    var cancelConnectCallCount = 0
    private var blockedConnectContinuation: CheckedContinuation<Bool, Never>?
    private var activeConnectCount = 0

    var state: KeyboardConnectionState { currentState }

    func availableKeyboards() async -> [KeyboardDescriptor] { [] }

    func stop() {}

    func refreshState() {
        if currentState == .failed {
            currentState = .disconnected
        }
        notify()
    }

    func connect() async -> Bool {
        connectCallCount += 1
        connectStartTimes.append(DispatchTime.now().uptimeNanoseconds)
        activeConnectCount += 1
        maximumConcurrentConnectCount = max(maximumConcurrentConnectCount, activeConnectCount)
        defer { activeConnectCount -= 1 }
        currentState = .connecting
        notify()

        if connectDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: connectDelayNanoseconds)
        }

        if blockNextConnect {
            blockNextConnect = false
            let success = await withCheckedContinuation { continuation in
                blockedConnectContinuation = continuation
            }
            currentState = success ? .connectedLocal : .failed
            notify()
            return success
        }

        if failNextConnects > 0 {
            failNextConnects -= 1
            lastError = "Pairing timed out"
            currentState = .failed
            notify()
            return false
        }

        currentState = .connectedLocal
        notify()
        return true
    }

    func cancelConnect() {
        cancelConnectCallCount += 1
        completeBlockedConnect(success: false)
    }

    func disconnect() async -> Bool {
        disconnectCallCount += 1
        currentState = .disconnecting
        notify()
        if failNextDisconnects > 0 {
            failNextDisconnects -= 1
            lastError = "Bluetooth operation failed"
            currentState = .failed
            notify()
            return false
        }
        currentState = .disconnected
        notify()
        return true
    }

    func completeBlockedConnect(success: Bool) {
        blockedConnectContinuation?.resume(returning: success)
        blockedConnectContinuation = nil
    }

    func waitUntilConnectCount(_ count: Int) async {
        while connectCallCount < count {
            await Task.yield()
        }
    }

    func waitUntilConnectIsBlocked() async {
        while blockedConnectContinuation == nil {
            await Task.yield()
        }
    }

    private func notify() {
        onStateChange?(currentState)
    }
}
