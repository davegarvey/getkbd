import XCTest
@testable import GetKbd

@MainActor
final class OwnershipControllerTests: XCTestCase {
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
        let controller = OwnershipController(keyboard: keyboard, claimRetryDelaysNanoseconds: [60_000_000_000])

        controller.start(monitorPresent: true, usbHubPresent: true)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        XCTAssertEqual(keyboard.connectCallCount, 1)
        XCTAssertTrue(controller.snapshot.isRetryingClaim)
        XCTAssertFalse(controller.snapshot.isBusy)
    }

    func testRetryLoopEndsAfterLastRetry() async {
        let keyboard = FakeKeyboardController()
        keyboard.failNextConnects = 2
        let controller = OwnershipController(keyboard: keyboard, claimRetryDelaysNanoseconds: [0])

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
        let controller = OwnershipController(keyboard: keyboard, claimRetryDelaysNanoseconds: [60_000_000_000])

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

    func testFailedTryNowRestartsTheRetrySchedule() async throws {
        let keyboard = FakeKeyboardController()
        keyboard.blockNextConnect = true
        keyboard.failNextConnects = 1
        let controller = OwnershipController(keyboard: keyboard, claimRetryDelaysNanoseconds: [60_000_000_000])

        controller.start(monitorPresent: true, usbHubPresent: true)
        await keyboard.waitUntilConnectIsBlocked()
        controller.connectNow()
        try await Task.sleep(nanoseconds: 2_000_000_000)

        XCTAssertEqual(keyboard.connectCallCount, 2)
        XCTAssertTrue(controller.snapshot.isRetryingClaim)
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
}

@MainActor
private final class FakeKeyboardController: KeyboardControlling {
    var configuredKeyboard: KeyboardDescriptor? = KeyboardDescriptor(
        identifier: "keyboard",
        name: "Shared Keyboard"
    )
    var currentState: KeyboardConnectionState = .disconnected
    var lastError: String?
    var onStateChange: ((KeyboardConnectionState) -> Void)?
    var connectCallCount = 0
    var disconnectCallCount = 0
    var blockNextConnect = false
    var failNextConnects = 0
    var cancelConnectCallCount = 0
    private var blockedConnectContinuation: CheckedContinuation<Bool, Never>?

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
        currentState = .connecting
        notify()

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
