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
        display.events.removeAll()

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
        display.events.removeAll()

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
    private var blockedConnectContinuation: CheckedContinuation<Bool, Never>?

    var state: KeyboardConnectionState { currentState }

    func availableKeyboards() async -> [KeyboardDescriptor] { [] }

    func stop() {}

    func refreshState() {
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

        currentState = .connectedLocal
        notify()
        return true
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

    func waitUntilConnectIsBlocked() async {
        while blockedConnectContinuation == nil {
            await Task.yield()
        }
    }

    private func notify() {
        onStateChange?(currentState)
    }
}
