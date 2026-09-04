import XCTest
@testable import GetKbd

@MainActor
final class DisplayPrimaryTests: XCTestCase {
    func testHubPresentTargetsActiveSelectedExternalDisplay() {
        let displays = [
            display("built-in", builtIn: true, active: true, x: 0),
            display("external", builtIn: false, active: true, x: 1440)
        ]

        XCTAssertEqual(
            DisplayPrimaryPlanner.targetIdentifier(
                configuredDisplayIdentifier: "external",
                hubConfigured: true,
                hubPresent: true,
                isSleeping: false,
                displays: displays
            ),
            "external"
        )
    }

    func testHubAbsentTargetsActiveBuiltInDisplay() {
        let displays = [
            display("built-in", builtIn: true, active: true, x: -1440),
            display("external", builtIn: false, active: true, x: 0)
        ]

        XCTAssertEqual(
            DisplayPrimaryPlanner.targetIdentifier(
                configuredDisplayIdentifier: "external",
                hubConfigured: true,
                hubPresent: false,
                isSleeping: false,
                displays: displays
            ),
            "built-in"
        )
    }

    func testHubAbsentWithInactiveBuiltInIsNoOp() {
        let displays = [
            display("built-in", builtIn: true, active: false, x: nil),
            display("external", builtIn: false, active: true, x: 0)
        ]

        XCTAssertNil(
            DisplayPrimaryPlanner.targetIdentifier(
                configuredDisplayIdentifier: "external",
                hubConfigured: true,
                hubPresent: false,
                isSleeping: false,
                displays: displays
            )
        )
    }

    func testMissingOrUnavailableSignalsDoNotSelectTarget() {
        let displays = [
            display("built-in", builtIn: true, active: true, x: 0),
            DisplayPrimarySnapshot(
                identifier: "external",
                isBuiltIn: false,
                isOnline: false,
                isActive: false,
                originX: nil,
                originY: nil,
                isMirrored: false
            )
        ]

        XCTAssertNil(
            DisplayPrimaryPlanner.targetIdentifier(
                configuredDisplayIdentifier: "external",
                hubConfigured: true,
                hubPresent: true,
                isSleeping: false,
                displays: displays
            )
        )
        XCTAssertNil(
            DisplayPrimaryPlanner.targetIdentifier(
                configuredDisplayIdentifier: nil,
                hubConfigured: false,
                hubPresent: false,
                isSleeping: false,
                displays: displays
            )
        )
    }

    func testOriginTranslationPreservesRelativeArrangement() {
        let displays = [
            display("built-in", builtIn: true, active: true, x: -1440),
            display("external", builtIn: false, active: true, x: 0)
        ]

        let origins = DisplayPrimaryPlanner.translatedOrigins(
            targetIdentifier: "built-in",
            displays: displays
        )
        let byIdentifier = Dictionary(uniqueKeysWithValues: origins!.map { ($0.identifier, $0) })

        XCTAssertEqual(byIdentifier["built-in"]?.x, 0)
        XCTAssertEqual(byIdentifier["external"]?.x, 1440)
        XCTAssertEqual(
            byIdentifier["external"]!.x - byIdentifier["built-in"]!.x,
            1440
        )
    }

    func testMonitorAppliesTargetAndSkipsAlreadyPrimaryTarget() {
        let system = FakeDisplayPrimarySystem(
            snapshots: [
                display("built-in", builtIn: true, active: true, x: -1440),
                display("external", builtIn: false, active: true, x: 0)
            ],
            mainIdentifier: "external"
        )
        let monitor = DisplayMonitor(
            configuredDisplayIdentifier: "external",
            primaryDisplaySystem: system
        )

        monitor.updatePrimaryHubSignal(configured: true, present: false)

        XCTAssertEqual(system.applyCallCount, 1)
        XCTAssertEqual(system.mainIdentifier, "built-in")

        monitor.updatePrimaryHubSignal(configured: true, present: true)
        XCTAssertEqual(system.applyCallCount, 2)

        monitor.updatePrimaryHubSignal(configured: true, present: true)
        XCTAssertEqual(system.applyCallCount, 2)
    }

    func testMonitorDoesNotApplyPrimaryChangeInClamshellWithoutHub() {
        let system = FakeDisplayPrimarySystem(
            snapshots: [
                display("built-in", builtIn: true, active: false, x: nil),
                display("external", builtIn: false, active: true, x: 0)
            ],
            mainIdentifier: "external"
        )
        let monitor = DisplayMonitor(
            configuredDisplayIdentifier: "external",
            primaryDisplaySystem: system
        )

        monitor.updatePrimaryHubSignal(configured: true, present: false)

        XCTAssertEqual(system.applyCallCount, 0)
        XCTAssertEqual(system.mainIdentifier, "external")
    }

    func testSleepingSuppressesPrimaryChangeUntilWake() async {
        let system = FakeDisplayPrimarySystem(
            snapshots: [
                display("built-in", builtIn: true, active: true, x: -1440),
                display("external", builtIn: false, active: true, x: 0)
            ],
            mainIdentifier: "external"
        )
        let monitor = DisplayMonitor(
            configuredDisplayIdentifier: "external",
            debounceInterval: 0,
            primaryDisplaySystem: system
        )

        monitor.setPrimaryDisplaySleeping(true)
        monitor.updatePrimaryHubSignal(configured: true, present: false)
        XCTAssertEqual(system.applyCallCount, 0)

        monitor.setPrimaryDisplaySleeping(false)
        for _ in 0..<100 where system.applyCallCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(system.applyCallCount, 1)
        XCTAssertEqual(system.mainIdentifier, "built-in")
        monitor.stop()
    }

    func testPrimaryOnlyDisplayChangeTriggersSynchronization() async {
        let system = FakeDisplayPrimarySystem(
            snapshots: [
                display("built-in", builtIn: true, active: true, x: -1440),
                display("external", builtIn: false, active: true, x: 0)
            ],
            mainIdentifier: "built-in"
        )
        let monitor = DisplayMonitor(
            configuredDisplayIdentifier: "external",
            debounceInterval: 0,
            primaryDisplaySystem: system
        )
        _ = monitor.start()
        monitor.updatePrimaryHubSignal(configured: true, present: false)

        system.mainIdentifier = "external"
        monitor.scheduleEvaluation()
        for _ in 0..<100 where system.applyCallCount == 0 {
            await Task.yield()
        }

        XCTAssertEqual(system.applyCallCount, 1)
        XCTAssertEqual(system.mainIdentifier, "built-in")
        monitor.stop()
    }

    func testWakeWithHubPresentTargetsExternalDisplay() async {
        let system = FakeDisplayPrimarySystem(
            snapshots: [
                display("built-in", builtIn: true, active: true, x: 0),
                display("external", builtIn: false, active: true, x: 1440)
            ],
            mainIdentifier: "built-in"
        )
        let monitor = DisplayMonitor(
            configuredDisplayIdentifier: "external",
            debounceInterval: 0,
            primaryDisplaySystem: system
        )

        monitor.setPrimaryDisplaySleeping(true)
        monitor.updatePrimaryHubSignal(configured: true, present: true)
        monitor.setPrimaryDisplaySleeping(false)
        for _ in 0..<100 where system.applyCallCount == 0 {
            await Task.yield()
        }

        XCTAssertEqual(system.applyCallCount, 1)
        XCTAssertEqual(system.mainIdentifier, "external")
        monitor.stop()
    }

    func testWakeUsesFreshHubSignalBeforeForcedEvaluation() async {
        let system = FakeDisplayPrimarySystem(
            snapshots: [
                display("built-in", builtIn: true, active: true, x: -1440),
                display("external", builtIn: false, active: true, x: 0)
            ],
            mainIdentifier: "built-in"
        )
        let monitor = DisplayMonitor(
            configuredDisplayIdentifier: "external",
            debounceInterval: 50.0 / 1_000.0,
            primaryDisplaySystem: system
        )

        monitor.setPrimaryDisplaySleeping(true)
        monitor.updatePrimaryHubSignal(configured: true, present: true)

        monitor.setPrimaryDisplaySleeping(false)
        monitor.updatePrimaryHubSignal(configured: true, present: false)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(system.applyCallCount, 1)
        XCTAssertEqual(system.mainIdentifier, "built-in")
        monitor.stop()
    }

    func testActiveDisplayChangeSynchronizesOnceForRepeatedNotifications() async {
        let system = FakeDisplayPrimarySystem(
            snapshots: [
                display("built-in", builtIn: true, active: false, x: nil),
                display("external", builtIn: false, active: true, x: 0)
            ],
            mainIdentifier: "external"
        )
        let monitor = DisplayMonitor(
            configuredDisplayIdentifier: "external",
            debounceInterval: 0,
            primaryDisplaySystem: system
        )
        _ = monitor.start()
        monitor.updatePrimaryHubSignal(configured: true, present: false)
        system.snapshotsValue = [
            display("built-in", builtIn: true, active: true, x: -1440),
            display("external", builtIn: false, active: true, x: 0)
        ]

        monitor.scheduleEvaluation()
        for _ in 0..<100 where system.applyCallCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(system.applyCallCount, 1)
        XCTAssertEqual(system.mainIdentifier, "built-in")

        monitor.scheduleEvaluation()
        monitor.scheduleEvaluation()
        for _ in 0..<10 {
            await Task.yield()
        }
        XCTAssertEqual(system.applyCallCount, 1)
        monitor.stop()
    }

    func testDisplayConfigurationFailureDoesNotChangeCurrentPrimary() {
        let system = FakeDisplayPrimarySystem(
            snapshots: [
                display("built-in", builtIn: true, active: true, x: -1440),
                display("external", builtIn: false, active: true, x: 0)
            ],
            mainIdentifier: "external",
            applyResult: false
        )
        let monitor = DisplayMonitor(
            configuredDisplayIdentifier: "external",
            primaryDisplaySystem: system
        )

        monitor.updatePrimaryHubSignal(configured: true, present: false)

        XCTAssertEqual(system.applyCallCount, 1)
        XCTAssertEqual(system.mainIdentifier, "external")
    }

    func testDisplayConfigurationFailureDoesNotBlockKeyboardClaim() async {
        let system = FakeDisplayPrimarySystem(
            snapshots: [
                display("built-in", builtIn: true, active: true, x: 0),
                display("external", builtIn: false, active: true, x: 1440)
            ],
            mainIdentifier: "built-in",
            applyResult: false
        )
        let monitor = DisplayMonitor(
            configuredDisplayIdentifier: "external",
            primaryDisplaySystem: system
        )
        monitor.updatePrimaryHubSignal(configured: true, present: true)

        let keyboard = DisplayTestKeyboard()
        let ownership = OwnershipController(keyboard: keyboard)
        ownership.start(monitorPresent: true, usbHubPresent: true)
        await ownership.waitForIdle()

        XCTAssertEqual(system.applyCallCount, 1)
        XCTAssertEqual(keyboard.connectCallCount, 1)
        XCTAssertEqual(keyboard.state, .connectedLocal)
    }

    private func display(
        _ identifier: String,
        builtIn: Bool,
        active: Bool,
        x: Int32?
    ) -> DisplayPrimarySnapshot {
        DisplayPrimarySnapshot(
            identifier: identifier,
            isBuiltIn: builtIn,
            isOnline: true,
            isActive: active,
            originX: x,
            originY: x.map { _ in 0 },
            isMirrored: false
        )
    }
}

@MainActor
private final class FakeDisplayPrimarySystem: DisplayPrimarySystem {
    var snapshotsValue: [DisplayPrimarySnapshot]
    var mainIdentifier: String?
    var applyResult: Bool
    var applyCallCount = 0

    init(
        snapshots: [DisplayPrimarySnapshot],
        mainIdentifier: String?,
        applyResult: Bool = true
    ) {
        snapshotsValue = snapshots
        self.mainIdentifier = mainIdentifier
        self.applyResult = applyResult
    }

    func snapshots() -> [DisplayPrimarySnapshot] {
        snapshotsValue
    }

    func mainDisplayIdentifier() -> String? {
        mainIdentifier
    }

    func apply(origins: [DisplayOrigin]) -> Bool {
        applyCallCount += 1
        guard applyResult else { return false }
        mainIdentifier = origins.first(where: { $0.x == 0 && $0.y == 0 })?.identifier
        return true
    }
}

@MainActor
private final class DisplayTestKeyboard: KeyboardControlling {
    var configuredKeyboard: KeyboardDescriptor? = KeyboardDescriptor(
        identifier: "keyboard",
        name: "Shared Keyboard"
    )
    var state: KeyboardConnectionState = .disconnected
    var lastError: String?
    var onStateChange: ((KeyboardConnectionState) -> Void)?
    var connectCallCount = 0

    func availableKeyboards() async -> [KeyboardDescriptor] { [] }

    func stop() {}

    func refreshState() {
        onStateChange?(state)
    }

    func connect() async -> Bool {
        connectCallCount += 1
        state = .connectedLocal
        onStateChange?(state)
        return true
    }

    func disconnect() async -> Bool {
        state = .disconnected
        onStateChange?(state)
        return true
    }
}
