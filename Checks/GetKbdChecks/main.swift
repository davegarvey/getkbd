import Foundation
import AppKit

@main
struct GetKbdChecks {
    static func main() async {
        check(
            normalizedBluetoothIdentifier("AA-BB:CC") == "aabbcc",
            "Bluetooth identifier normalization"
        )

        check(AppSettings.initial.needsOnboarding, "initial settings require setup")

        let configured = KeyboardDescriptor(identifier: "keyboard-1", name: "Shared Keyboard")
        var settings = AppSettings.initial
        settings.selectedKeyboard = configured
        settings.selectedDisplay = DisplayDescriptor(
            identifier: "display-1",
            name: "Shared Display",
            isBuiltIn: false
        )
        let hub = USBHubDescriptor(
            identifier: "hub-1",
            name: "Switch Hub",
            manufacturer: "Switch Co",
            vendorID: 1,
            productID: 2
        )
        settings.selectedUSBHubs = [hub]
        check(!settings.needsOnboarding, "complete local settings are ready")

        await checkBluetoothPowerActivation()
        await checkBluetoothAvailability(settings)
        checkSettingsMigration()
        checkMenuStatus(settings)
        checkHubIdentification(hub)
        checkMonitorInputs(settings)
        await checkMonitorInputLearner()
        await checkClaimRetries()

        print("GetKbd checks passed.")
    }

    @MainActor
    private static func checkBluetoothPowerActivation() async {
        let iconSnapshot = OwnershipSnapshot(keyboardState: .disconnected, ownershipReason: .none,
                                             monitorPresent: false, usbHubPresent: false, isBusy: false,
                                             errorMessage: nil, bluetoothAvailability: .poweredOff)
        let icon = MenuBarController.statusImage(for: iconSnapshot, title: "Bluetooth is off")
        check(icon?.isTemplate == true && icon?.size == NSSize(width: 22, height: 18),
              "Bluetooth warning keeps keyboard with a template badge")
        let preview = NSImage(size: NSSize(width: 220, height: 180), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            icon?.draw(in: rect)
            return true
        }
        if let output = ProcessInfo.processInfo.environment["GETKBD_ICON_PREVIEW"],
           let tiff = preview.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try! png.write(to: URL(fileURLWithPath: output))
        }
        var availability = BluetoothAvailability.poweredOff
        var requests = 0
        let activation = BluetoothPowerController(requestPowerOn: {
            requests += 1
            availability = .poweredOn
            return true
        }, availability: { availability })
        let enabled = await activation.enable()
        check(enabled && requests == 1, "Direct activation verifies power on")
        let alreadyEnabled = await activation.enable()
        check(alreadyEnabled && requests == 1, "Already enabled Bluetooth needs no power request")

        let missingAPI = BluetoothPowerController(requestPowerOn: { false }, availability: { .poweredOff })
        let missingResult = await missingAPI.enable()
        check(!missingResult, "Missing private power API fails safely")
        let ignoredRequest = BluetoothPowerController(timeout: .zero, requestPowerOn: { true }, availability: { .poweredOff })
        let ignoredResult = await ignoredRequest.enable()
        check(!ignoredResult, "Unconfirmed activation times out instead of reporting success")
        var reads = 0
        let delayed = BluetoothPowerController(requestPowerOn: { true }, availability: {
            reads += 1
            return reads >= 3 ? .poweredOn : .poweredOff
        })
        let delayedResult = await delayed.enable()
        check(delayedResult, "Asynchronous controller activation is observed")

        let off = OwnershipSnapshot(keyboardState: .disconnected, ownershipReason: .none,
                                    monitorPresent: false, usbHubPresent: false, isBusy: false,
                                    errorMessage: nil, bluetoothAvailability: .poweredOff)
        let pending = MenuStatus.make(settings: .initial, snapshot: off, desiredState: nil,
                                      bluetoothActivation: .enabling)
        check(pending.title == "Turning Bluetooth on…" && pending.action == nil,
              "Pending activation suppresses repeated menu actions")
        let failed = MenuStatus.make(settings: .initial, snapshot: off, desiredState: nil,
                                     bluetoothActivation: .failed)
        check(failed.title == "Couldn’t turn Bluetooth on" && failed.action == .bluetoothSettings,
              "Failed activation offers Bluetooth Settings")
    }

    @MainActor
    private static func checkBluetoothAvailability(_ settings: AppSettings) async {
        for availability in [BluetoothAvailability.poweredOff, .unavailable] {
            let snapshot = OwnershipSnapshot(keyboardState: .failed, ownershipReason: .none,
                                             monitorPresent: true, usbHubPresent: true,
                                             isBusy: false, errorMessage: "Pairing failed",
                                             bluetoothAvailability: availability)
            var withInputs = settings
            withInputs.monitorInputs = LearnedMonitorInputs(displayIdentifier: "display-1", thisMac: 19, otherMac: 21)
            let status = MenuStatus.make(settings: withInputs, snapshot: snapshot, desiredState: .connected,
                                         monitorControlAvailable: true)
            check(status.title == availability.title && status.action == (availability == .poweredOff ? .enableBluetooth : .bluetoothSettings),
                  "Bluetooth availability overrides retry")
            check(status.monitorAction == .switchToOtherMac, "Bluetooth off preserves monitor switching")
        }
        let keyboard = CheckKeyboardController()
        keyboard.bluetoothAvailability = .poweredOff
        let ownership = OwnershipController(keyboard: keyboard)
        ownership.start(monitorPresent: true, usbHubPresent: true)
        ownership.manualClaim()
        ownership.manualRelease()
        await ownership.waitForIdle()
        check(keyboard.claims == 0 && keyboard.releases == 0, "Bluetooth off blocks keyboard operations")
        keyboard.setAvailability(.poweredOn)
        await ownership.waitForIdle()
        check(keyboard.claims == 1, "Bluetooth restoration resumes automatic claim")

        ownership.usbHubDisconnected()
        await ownership.waitForIdle()
        ownership.usbHubConnected()
        keyboard.setAvailability(.poweredOff)
        await ownership.waitForIdle()
        check(keyboard.claims == 1, "Bluetooth off cancels pending claim")
        ownership.usbHubDisconnected()
        keyboard.setAvailability(.poweredOn)
        await ownership.waitForIdle()
        check(keyboard.claims == 1, "Bluetooth restoration respects current hub signal")

        keyboard.blockNextClaim = true
        ownership.usbHubConnected()
        while keyboard.blockedClaim == nil { await Task.yield() }
        keyboard.setAvailability(.poweredOff)
        keyboard.blockedClaim?.resume(returning: false)
        keyboard.blockedClaim = nil
        await ownership.waitForIdle()
        check(keyboard.claims == 2, "Power loss during claim suppresses retries")
        keyboard.setAvailability(.poweredOn)
        await ownership.waitForIdle()
        check(keyboard.claims == 3, "Claim interrupted by power loss recovers")
    }

    private static func checkSettingsMigration() {
        let legacy = """
        {"selectedUSBHub": {"identifier": "hub-1", "name": "Hub", "manufacturer": "", "vendorID": 1, "productID": 2},
         "shortcut": {"keyCode": 40, "modifiers": 6400}}
        """
        let decoded = try? JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        check(decoded?.selectedUSBHubs.map(\.identifier) == ["hub-1"], "legacy hub migrates to a group")
        check(decoded?.switchMainDisplay == true, "main-display preference defaults on")

        let encoded = decoded.flatMap { try? JSONEncoder().encode($0) }
        let roundTrip = encoded.flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) }
        check(roundTrip == decoded, "settings round-trip")
    }

    private static func checkMenuStatus(_ settings: AppSettings) {
        func status(_ state: KeyboardConnectionState, monitor: Bool = true, hub: Bool) -> MenuStatus {
            MenuStatus.make(
                settings: settings,
                snapshot: OwnershipSnapshot(
                    keyboardState: state,
                    ownershipReason: .none,
                    monitorPresent: monitor,
                    usbHubPresent: hub,
                    isBusy: false,
                    errorMessage: nil
                ),
                desiredState: nil
            )
        }

        check(status(.connectedLocal, hub: true).action == .release, "connected keyboard offers release")
        check(status(.disconnected, hub: false).action == nil, "other Mac state offers no action")
        check(status(.disconnected, hub: true).action == .get, "monitor here offers get")
        check(status(.disconnected, monitor: false, hub: false).action == .get, "offline monitor offers get")
        check(status(.failed, hub: true).action == .retry, "failure offers retry")

        let connecting = status(.connecting, hub: true)
        check(connecting.title == "Connecting keyboard…" && connecting.action == .tryNow, "claim in progress offers try now")
        check(status(.disconnecting, hub: false).action == nil, "release in progress offers no action")

        let retrying = MenuStatus.make(
            settings: settings,
            snapshot: OwnershipSnapshot(
                keyboardState: .disconnected,
                ownershipReason: .usbHub,
                monitorPresent: true,
                usbHubPresent: true,
                isBusy: false,
                errorMessage: "Bluetooth pairing timed out",
                isRetryingClaim: true
            ),
            desiredState: .connected
        )
        check(retrying.title == "Keyboard isn’t responding" && retrying.action == .tryNow, "retry loop offers try now")
    }

    private static func checkHubIdentification(_ hub: USBHubDescriptor) {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let stick = USBHubDescriptor(identifier: "stick", name: "Stick", manufacturer: "", vendorID: 3, productID: 4)

        var identification = HubIdentification(hubs: [hub], at: start)
        identification.observe([hub, stick], at: start + 1)
        identification.tick(at: start + 3)
        identification.observe([stick], at: start + 5)
        identification.tick(at: start + 7)
        check(identification.phase == .waitingForSwitchBack, "identification waits for the switch back")
        identification.observe([hub, stick], at: start + 10)
        identification.tick(at: start + 12)
        check(identification.phase == .succeeded([hub]), "identification keeps hubs that return and drops one-way changes")

        var timedOut = HubIdentification(hubs: [hub], at: start)
        timedOut.tick(at: start + HubIdentification.timeout)
        check(timedOut.phase == .timedOut, "identification times out")
    }

    private static func checkMonitorInputs(_ settings: AppSettings) {
        let captured: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x60, 0x00, 0x00, 0x15, 0x00, 0x13, 0xD2, 0x00]
        check(DDCInputReply.currentValue(from: captured) == 19, "input reply parses")
        var unsupported = captured
        unsupported[3] = 0x01
        check(DDCInputReply.currentValue(from: unsupported) == nil, "unsupported reply is rejected")
        check(DDCInputReply.currentValue(from: Array(captured.prefix(6))) == nil, "short reply is rejected")

        let identifier = settings.selectedDisplay?.identifier ?? ""
        let thisMac = LearnedMonitorInputs.recording(19, forThisMac: true, displayIdentifier: identifier, into: nil)
        let both = LearnedMonitorInputs.recording(21, forThisMac: false, displayIdentifier: identifier, into: thisMac)
        check(both?.thisMac == 19 && both?.otherMac == 21, "both monitor inputs are learned")
        check(
            LearnedMonitorInputs.recording(19, forThisMac: false, displayIdentifier: identifier, into: both) == nil,
            "conflicting monitor input is discarded"
        )

        var withInputs = settings
        withInputs.monitorInputs = both
        func monitorAction(hub: Bool, available: Bool = true) -> MonitorAction? {
            MenuStatus.make(
                settings: withInputs,
                snapshot: OwnershipSnapshot(
                    keyboardState: hub ? .connectedLocal : .disconnected,
                    ownershipReason: .none,
                    monitorPresent: true,
                    usbHubPresent: hub,
                    isBusy: false,
                    errorMessage: nil
                ),
                desiredState: nil,
                monitorControlAvailable: available
            ).monitorAction
        }
        check(monitorAction(hub: true) == .switchToOtherMac, "active Mac offers switch to other Mac")
        check(monitorAction(hub: false) == .switchToThisMac, "inactive Mac offers switch to this Mac")
        check(monitorAction(hub: false, available: false) == nil, "unavailable monitor control hides the action")
    }

    @MainActor
    private static func checkMonitorInputLearner() async {
        final class Control: MonitorInputControl, @unchecked Sendable {
            var readings: [Int?]
            init(_ readings: [Int?]) { self.readings = readings }
            func readInput(displayIdentifier: String) async -> Int? { readings.isEmpty ? nil : readings.removeFirst() }
            func setInput(_ value: Int, displayIdentifier: String) async -> Bool { true }
        }

        let learner = MonitorInputLearner(control: Control([nil, 21, 19, 21, 21]), readingInterval: 0)
        var recorded: (Int, Bool)?
        learner.onReading = { value, isThisMac, _ in recorded = (value, isThisMac) }
        learner.learn(displayIdentifier: "d", hubPresent: false)
        await learner.waitForIdle()
        check(recorded?.0 == 21 && recorded?.1 == false, "learner accepts two agreeing readings")

        let silent = MonitorInputLearner(control: Control([]), readingInterval: 0, maximumReadings: 3)
        var available: Bool?
        silent.onAvailabilityChange = { available = $0 }
        silent.learn(displayIdentifier: "d", hubPresent: true)
        await silent.waitForIdle()
        check(available == false, "silent monitor is reported unavailable")
    }

    @MainActor
    private static func checkClaimRetries() async {
        final class Keyboard: KeyboardControlling {
            var configuredKeyboard: KeyboardDescriptor? = KeyboardDescriptor(identifier: "k", name: "Keyboard")
            var state: KeyboardConnectionState = .disconnected
            var lastError: String?
            var onStateChange: ((KeyboardConnectionState) -> Void)?
            var connectCount = 0
            var cancelCount = 0
            var failures = 0
            var blockNext = false
            var blocked: CheckedContinuation<Bool, Never>?

            func availableKeyboards() async -> [KeyboardDescriptor] { [] }
            func stop() {}
            func refreshState() {
                if state == .failed { state = .disconnected }
                onStateChange?(state)
            }
            func connect() async -> Bool {
                connectCount += 1
                state = .connecting
                onStateChange?(state)
                var succeeded = true
                if blockNext {
                    blockNext = false
                    succeeded = await withCheckedContinuation { blocked = $0 }
                } else if failures > 0 {
                    failures -= 1
                    succeeded = false
                }
                state = succeeded ? .connectedLocal : .failed
                onStateChange?(state)
                return succeeded
            }
            func cancelConnect() {
                cancelCount += 1
                blocked?.resume(returning: false)
                blocked = nil
            }
            func disconnect() async -> Bool {
                state = .disconnected
                onStateChange?(state)
                return true
            }
        }

        let longDelay: [UInt64] = [60_000_000_000]

        // A failed claim must wait for its scheduled retry, not the 0.75 s USB-hub claim.
        let failing = Keyboard()
        failing.failures = 1
        let waiting = OwnershipController(keyboard: failing, claimRetryDelaysNanoseconds: longDelay)
        waiting.start(monitorPresent: true, usbHubPresent: true)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        check(failing.connectCount == 1, "failed claim waits for its scheduled retry")
        check(waiting.snapshot.isRetryingClaim, "pending retry is reported")

        waiting.connectNow()
        await waiting.waitForIdle()
        check(failing.connectCount == 2, "try now claims while a retry is pending")
        check(waiting.snapshot.keyboardState == .connectedLocal, "try now connects")
        check(waiting.snapshot.ownershipReason == .usbHub, "try now keeps the automatic target")
        check(!waiting.snapshot.isRetryingClaim, "success ends the retry loop")

        let exhausted = Keyboard()
        exhausted.failures = 2
        let finishing = OwnershipController(keyboard: exhausted, claimRetryDelaysNanoseconds: [0])
        finishing.start(monitorPresent: true, usbHubPresent: true)
        while exhausted.connectCount < 2 { await Task.yield() }
        await finishing.waitForIdle()
        check(exhausted.connectCount == 2 && !finishing.snapshot.isRetryingClaim, "retry loop ends after the last retry")

        let stuck = Keyboard()
        stuck.blockNext = true
        let restarting = OwnershipController(keyboard: stuck)
        restarting.start(monitorPresent: true, usbHubPresent: true)
        while stuck.blocked == nil { await Task.yield() }
        restarting.connectNow()
        await restarting.waitForIdle()
        check(stuck.cancelCount == 1 && stuck.connectCount == 2, "try now stops a claim in progress and starts another")
        check(restarting.snapshot.keyboardState == .connectedLocal, "restarted claim connects")
        check(restarting.snapshot.errorMessage == nil, "cancelled claim leaves no error")

        let stuckAgain = Keyboard()
        stuckAgain.blockNext = true
        stuckAgain.failures = 1
        let rescheduling = OwnershipController(keyboard: stuckAgain, claimRetryDelaysNanoseconds: longDelay)
        rescheduling.start(monitorPresent: true, usbHubPresent: true)
        while stuckAgain.blocked == nil { await Task.yield() }
        rescheduling.connectNow()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        check(stuckAgain.connectCount == 2 && rescheduling.snapshot.isRetryingClaim, "failed try now returns to the retry schedule")
    }

    private static func check(_ condition: Bool, _ name: String) {
        precondition(condition, "Check failed: \(name)")
    }
}

@MainActor
private final class CheckKeyboardController: KeyboardControlling {
    var configuredKeyboard: KeyboardDescriptor? = KeyboardDescriptor(identifier: "keyboard", name: "Keyboard")
    var state: KeyboardConnectionState = .disconnected
    var bluetoothAvailability: BluetoothAvailability = .poweredOn
    var lastError: String?
    var onStateChange: ((KeyboardConnectionState) -> Void)?
    var onBluetoothAvailabilityChange: (() -> Void)?
    var claims = 0
    var releases = 0
    var blockNextClaim = false
    var blockedClaim: CheckedContinuation<Bool, Never>?

    func setAvailability(_ availability: BluetoothAvailability) {
        bluetoothAvailability = availability
        if availability != .poweredOn { state = .disconnected }
        onBluetoothAvailabilityChange?()
    }
    func availableKeyboards() async -> [KeyboardDescriptor] { [] }
    func stop() {}
    func refreshState() { onStateChange?(state) }
    func connect() async -> Bool {
        claims += 1
        state = .connecting
        onStateChange?(state)
        var success = true
        if blockNextClaim {
            blockNextClaim = false
            success = await withCheckedContinuation { blockedClaim = $0 }
        }
        state = success ? .connectedLocal : .failed
        onStateChange?(state)
        return success
    }
    func disconnect() async -> Bool {
        releases += 1
        state = .disconnected
        onStateChange?(state)
        return true
    }
}
