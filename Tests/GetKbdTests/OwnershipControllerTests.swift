import XCTest
@testable import GetKbd

@MainActor
final class OwnershipControllerTests: XCTestCase {
    func testMonitorConnectionClaimsAndDisconnectionReleases() async {
        let keyboard = FakeKeyboardController()
        let controller = OwnershipController(keyboard: keyboard, behavior: .allEnabled)

        controller.start(monitorPresent: false)
        controller.monitorConnected()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.connectCallCount, 1)
        XCTAssertEqual(controller.snapshot.keyboardState, .connectedLocal)
        XCTAssertEqual(controller.snapshot.ownershipReason, .monitor)

        controller.monitorDisconnected()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.disconnectCallCount, 1)
        XCTAssertEqual(controller.snapshot.keyboardState, .disconnected)
        XCTAssertEqual(controller.snapshot.ownershipReason, .none)
    }

    func testStartupClaimIsOwnedByTheMonitor() async {
        let keyboard = FakeKeyboardController()
        let controller = OwnershipController(keyboard: keyboard, behavior: .allEnabled)

        controller.start(monitorPresent: true)
        await controller.waitForIdle()

        XCTAssertEqual(controller.snapshot.ownershipReason, .monitor)

        controller.monitorDisconnected()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.disconnectCallCount, 1)
        XCTAssertEqual(controller.snapshot.keyboardState, .disconnected)
    }

    func testConnectedKeyboardAtDeskStartupIsMonitorOwned() async {
        let keyboard = FakeKeyboardController()
        keyboard.currentState = .connectedLocal
        let controller = OwnershipController(keyboard: keyboard, behavior: .allEnabled)

        controller.start(monitorPresent: true)
        await controller.waitForIdle()

        XCTAssertEqual(controller.snapshot.ownershipReason, .monitor)

        controller.monitorDisconnected()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.disconnectCallCount, 1)
        XCTAssertEqual(controller.snapshot.keyboardState, .disconnected)
    }

    func testManualOwnershipSurvivesMonitorDisconnection() async {
        let keyboard = FakeKeyboardController()
        let controller = OwnershipController(keyboard: keyboard, behavior: .allEnabled)

        controller.start(monitorPresent: false)
        controller.manualClaim()
        await controller.waitForIdle()
        controller.monitorDisconnected()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.connectCallCount, 1)
        XCTAssertEqual(keyboard.disconnectCallCount, 0)
        XCTAssertEqual(controller.snapshot.ownershipReason, .manual)
        XCTAssertEqual(controller.snapshot.keyboardState, .connectedLocal)
    }

    func testMonitorConnectionCanTakeOwnershipAfterManualClaim() async {
        let keyboard = FakeKeyboardController()
        let controller = OwnershipController(
            keyboard: keyboard,
            behavior: AutomaticBehavior(
                claimOnMonitorConnect: true,
                monitorTakesOwnershipFromManual: true,
                releaseOnMonitorDisconnect: true,
                releaseBeforeSleep: true
            )
        )

        controller.start(monitorPresent: false)
        controller.manualClaim()
        await controller.waitForIdle()

        controller.monitorConnected()
        await controller.waitForIdle()

        XCTAssertEqual(controller.snapshot.ownershipReason, .monitor)

        controller.monitorDisconnected()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.disconnectCallCount, 1)
        XCTAssertEqual(controller.snapshot.ownershipReason, .none)
    }

    func testUSBHubSourceIgnoresMonitorAndClaimsOnHubConnection() async {
        let keyboard = FakeKeyboardController()
        let controller = OwnershipController(keyboard: keyboard, behavior: .usbHub)

        controller.start(monitorPresent: true)
        controller.monitorConnected()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.connectCallCount, 0)
        XCTAssertEqual(controller.snapshot.ownershipReason, .none)

        controller.usbHubConnected()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.connectCallCount, 1)
        XCTAssertEqual(controller.snapshot.ownershipReason, .usbHub)
    }

    func testUSBHubOwnedKeyboardReleasesWhenMonitorDisconnects() async {
        let keyboard = FakeKeyboardController()
        keyboard.configuredKeyboard = KeyboardDescriptor(identifier: "keyboard", name: "Keyboard")
        let controller = OwnershipController(keyboard: keyboard, behavior: .usbHub)

        controller.start(monitorPresent: true)
        controller.usbHubConnected()
        await controller.waitForIdle()

        controller.monitorDisconnected()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.disconnectCallCount, 1)
        XCTAssertEqual(controller.snapshot.keyboardState, .disconnected)
        XCTAssertEqual(controller.snapshot.ownershipReason, .none)
    }

    func testUSBHubDisconnectReleasesSelectedExistingKeyboard() async {
        let keyboard = FakeKeyboardController()
        keyboard.configuredKeyboard = KeyboardDescriptor(identifier: "keyboard", name: "Keyboard")
        keyboard.currentState = .connectedLocal
        let controller = OwnershipController(keyboard: keyboard, behavior: .usbHub)

        controller.start(monitorPresent: true, usbHubPresent: true)
        await controller.waitForIdle()
        controller.usbHubDisconnected()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.disconnectCallCount, 1)
        XCTAssertEqual(controller.snapshot.keyboardState, .disconnected)
        XCTAssertEqual(controller.snapshot.ownershipReason, .none)
    }

    func testUSBHubDisconnectDoesNotReleaseUnconfiguredKeyboard() async {
        let keyboard = FakeKeyboardController()
        keyboard.currentState = .connectedLocal
        let controller = OwnershipController(keyboard: keyboard, behavior: .usbHub)

        controller.start(monitorPresent: true, usbHubPresent: true)
        await controller.waitForIdle()
        controller.usbHubDisconnected()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.disconnectCallCount, 0)
        XCTAssertEqual(controller.snapshot.keyboardState, .connectedLocal)
    }

    func testUSBHubSourceReleasesKeyboardLocally() async {
        let keyboard = FakeKeyboardController()
        keyboard.configuredKeyboard = KeyboardDescriptor(identifier: "keyboard", name: "Keyboard")
        keyboard.currentState = .connectedLocal
        let controller = OwnershipController(keyboard: keyboard, behavior: .usbHub)

        controller.start(monitorPresent: true, usbHubPresent: true)
        await controller.waitForIdle()
        controller.usbHubDisconnected()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.disconnectCallCount, 1)
        XCTAssertEqual(controller.snapshot.keyboardState, .disconnected)
        XCTAssertEqual(controller.snapshot.ownershipReason, .none)
    }

    func testChangingFromMonitorToKvmReleasesMonitorOwnership() async {
        let keyboard = FakeKeyboardController()
        let controller = OwnershipController(keyboard: keyboard, behavior: .allEnabled)

        controller.start(monitorPresent: true)
        await controller.waitForIdle()
        controller.updateBehavior(.usbHub, monitorPresent: true)
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.disconnectCallCount, 1)
        XCTAssertEqual(controller.snapshot.keyboardState, .disconnected)
        XCTAssertEqual(controller.snapshot.ownershipReason, .none)
    }

    func testChangingFromKvmToMonitorWithNoMonitorReleasesKeyboard() async {
        let keyboard = FakeKeyboardController()
        let controller = OwnershipController(keyboard: keyboard, behavior: .usbHub)

        controller.start(monitorPresent: true, usbHubPresent: true)
        await controller.waitForIdle()
        controller.updateBehavior(.allEnabled, monitorPresent: false, usbHubPresent: false)
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.disconnectCallCount, 1)
        XCTAssertEqual(controller.snapshot.keyboardState, .disconnected)
        XCTAssertEqual(controller.snapshot.ownershipReason, .none)
    }

    func testSleepReleasesManualOwnership() async {
        let keyboard = FakeKeyboardController()
        let controller = OwnershipController(keyboard: keyboard, behavior: .allEnabled)

        controller.manualClaim()
        await controller.waitForIdle()
        controller.willSleep()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.disconnectCallCount, 1)
        XCTAssertEqual(controller.snapshot.keyboardState, .disconnected)
        XCTAssertEqual(controller.snapshot.ownershipReason, .none)
    }

    func testExistingConnectionIsNotReleasedWhenMonitorIsAbsent() async {
        let keyboard = FakeKeyboardController()
        keyboard.currentState = .connectedLocal
        let controller = OwnershipController(keyboard: keyboard, behavior: .allEnabled)

        controller.start(monitorPresent: false)
        await controller.waitForIdle()
        controller.monitorDisconnected()
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.disconnectCallCount, 0)
        XCTAssertEqual(controller.snapshot.ownershipReason, .existing)
        XCTAssertEqual(controller.snapshot.keyboardState, .connectedLocal)
    }

    func testDisconnectDuringClaimIsReconciledAfterClaimCompletes() async {
        let keyboard = FakeKeyboardController()
        keyboard.blockNextConnect = true
        let controller = OwnershipController(keyboard: keyboard, behavior: .allEnabled)

        controller.start(monitorPresent: false)
        controller.monitorConnected()
        await keyboard.waitUntilConnectIsBlocked()
        controller.monitorDisconnected()

        keyboard.completeBlockedConnect(success: true)
        await controller.waitForIdle()

        XCTAssertEqual(keyboard.connectCallCount, 1)
        XCTAssertEqual(keyboard.disconnectCallCount, 1)
        XCTAssertEqual(controller.snapshot.keyboardState, .disconnected)
    }

    func testDisplayIsMirroredBeforeReleaseAndRestoredAfterClaim() async {
        let keyboard = FakeKeyboardController()
        keyboard.currentState = .connectedLocal
        let display = FakeDisplayHandoffController()
        let controller = OwnershipController(
            keyboard: keyboard,
            behavior: .allEnabled,
            displayHandoff: display
        )

        controller.start(monitorPresent: false)
        display.events.removeAll()
        controller.manualRelease()
        await controller.waitForIdle()
        controller.manualClaim()
        await controller.waitForIdle()

        XCTAssertEqual(display.events, [.mirror, .restore])
    }

    func testFailedReleaseKeepsDisplayMirrored() async {
        let keyboard = FakeKeyboardController()
        keyboard.currentState = .connectedLocal
        keyboard.failNextDisconnect = true
        let display = FakeDisplayHandoffController()
        let controller = OwnershipController(
            keyboard: keyboard,
            behavior: .allEnabled,
            displayHandoff: display
        )

        controller.start(monitorPresent: false)
        display.events.removeAll()
        controller.manualRelease()
        await controller.waitForIdle()

        XCTAssertEqual(display.events, [.mirror])
    }

    func testFailedReleaseRestoresDisplayIfKeyboardRemainsConnected() async {
        let keyboard = FakeKeyboardController()
        keyboard.currentState = .connectedLocal
        keyboard.failNextDisconnect = true
        keyboard.keepConnectedOnDisconnectFailure = true
        let display = FakeDisplayHandoffController()
        let controller = OwnershipController(
            keyboard: keyboard,
            behavior: .allEnabled,
            displayHandoff: display
        )

        controller.start(monitorPresent: false)
        display.events.removeAll()
        controller.manualRelease()
        await controller.waitForIdle()

        XCTAssertEqual(display.events, [.mirror, .restore])
    }
}

@MainActor
private final class FakeKeyboardController: KeyboardControlling {
    var configuredKeyboard: KeyboardDescriptor?
    var currentState: KeyboardConnectionState = .disconnected
    var lastError: String?
    var onStateChange: ((KeyboardConnectionState) -> Void)?
    var connectCallCount = 0
    var disconnectCallCount = 0
    var blockNextConnect = false
    var failNextDisconnect = false
    var keepConnectedOnDisconnectFailure = false
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
        let succeeds = !failNextDisconnect
        failNextDisconnect = false
        currentState = succeeds
            ? .disconnected
            : (keepConnectedOnDisconnectFailure ? .connectedLocal : .failed)
        keepConnectedOnDisconnectFailure = false
        notify()
        return succeeds
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

@MainActor
private final class FakeDisplayHandoffController: DisplayHandoffControlling {
    enum Event: Equatable {
        case mirror
        case restore
    }

    var events: [Event] = []
    var hasPendingKeyboardRelease = false

    func prepareForKeyboardRelease() {
        events.append(.mirror)
    }

    func restoreAfterKeyboardClaim() {
        events.append(.restore)
    }
}

private extension AutomaticBehavior {
    static let allEnabled = AutomaticBehavior(
        claimOnMonitorConnect: true,
        monitorTakesOwnershipFromManual: false,
        releaseOnMonitorDisconnect: true,
        releaseBeforeSleep: true
    )

    static let usbHub = AutomaticBehavior(
        claimOnMonitorConnect: true,
        monitorTakesOwnershipFromManual: false,
        releaseOnMonitorDisconnect: true,
        releaseBeforeSleep: true,
        automaticSource: .usbHub
    )
}
