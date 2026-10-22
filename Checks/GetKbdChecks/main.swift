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
        checkMonitorIdentity()
        await checkConnectionRecognition()
        await checkMonitorInputLearner()
        await checkClaimRetries()
        await checkDormantPairingRelease()
        await checkScreenWakeRecovery()
        await checkScreenNotificationRouting()

        print("GetKbd checks passed.")
    }

    @MainActor
    private static func checkScreenWakeRecovery() async {
        await checkScreenWakeGuards()
        for hubPresent in [false, true] {
            let system = CheckDisplayPrimarySystem(
                snapshots: [
                    display("built-in", builtIn: true, active: true, x: -1440),
                    display("external", builtIn: false, active: true, x: 0)
                ],
                mainIdentifier: hubPresent ? "built-in" : "external"
            )
            let monitor = DisplayMonitor(configuredMonitor: MonitorIdentity(name: "External", knownIdentifiers: ["external"]), debounceInterval: 0,
                                         primaryDisplaySystem: system)
            monitor.setPrimaryScreensSleeping(true)
            _ = monitor.start()
            monitor.updatePrimaryHubSignal(configured: true, present: hubPresent)
            monitor.scheduleEvaluation()
            for _ in 0..<100 { await Task.yield() }
            check(system.applyCallCount == 0, "Screen sleep defers primary changes")
            monitor.setPrimaryScreensSleeping(false)
            for _ in 0..<100 { await Task.yield() }
            check(system.mainIdentifier == (hubPresent ? "external" : "built-in"), "Screen wake selects the current hub target")
            check(system.applyCallCount == 1, "Screen wake forces one sync despite unchanged topology")
            monitor.stop()
        }
    }

    @MainActor
    private static func checkScreenWakeGuards() async {
        for condition in ["disabled", "clamshell", "system-sleep"] {
            let system = CheckDisplayPrimarySystem(
                snapshots: [
                    display("built-in", builtIn: true, active: condition != "clamshell",
                            x: condition == "clamshell" ? nil : -1440),
                    display("external", builtIn: false, active: true, x: 0)
                ],
                mainIdentifier: "external"
            )
            let monitor = DisplayMonitor(configuredMonitor: MonitorIdentity(name: "External", knownIdentifiers: ["external"]), debounceInterval: 0,
                                         primaryDisplaySystem: system)
            monitor.primarySyncEnabled = condition != "disabled"
            monitor.setPrimaryDisplaySleeping(condition == "system-sleep")
            monitor.setPrimaryScreensSleeping(true)
            monitor.updatePrimaryHubSignal(configured: true, present: false)
            monitor.setPrimaryScreensSleeping(false)
            for _ in 0..<100 { await Task.yield() }
            check(system.applyCallCount == 0, "Screen wake respects \(condition)")
            check(system.mainIdentifier == "external", "Screen wake retains primary under \(condition)")
            monitor.stop()
        }
    }

    private static func display(
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

    @MainActor
    private static func checkScreenNotificationRouting() async {
        let center = NotificationCenter()
        let monitor = SleepMonitor(notificationCenter: center)
        var screenSleeps = 0
        var screenWakes = 0
        var systemEvents = 0
        monitor.onScreensDidSleep = { screenSleeps += 1 }
        monitor.onScreensDidWake = { screenWakes += 1 }
        monitor.onWillSleep = { systemEvents += 1 }
        monitor.onDidWake = { systemEvents += 1 }
        monitor.start()
        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        for _ in 0..<100 { await Task.yield() }
        check(screenSleeps == 1, "Screen sleep notification routed")
        check(screenWakes == 1, "Screen wake notification routed and observers removed on stop")
        check(systemEvents == 0, "Screen events do not trigger system ownership recovery")
        monitor.stop()
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        for _ in 0..<100 { await Task.yield() }
        check(screenWakes == 1, "Screen wake notification routed and observers removed on stop")
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
            withInputs.setMonitorInputs(LearnedMonitorInputs(displayIdentifier: "display-1", thisMac: 19, otherMac: 21))
            let status = MenuStatus.make(settings: withInputs, snapshot: snapshot, desiredState: .connected,
                                         monitorControlAvailable: true)
            check(status.title == availability.title && status.action == (availability == .poweredOff ? .enableBluetooth : .bluetoothSettings),
                  "Bluetooth availability overrides retry")
            check(status.monitorAction == .switchToOtherMac, "Bluetooth off preserves monitor switching")
        }
        for paired in [false, true] {
            let snapshot = OwnershipSnapshot(keyboardState: .disconnected, ownershipReason: .none,
                                             monitorPresent: true, usbHubPresent: false, isBusy: false,
                                             errorMessage: nil, bluetoothAvailability: .poweredOff,
                                             keyboardPaired: paired)
            let status = MenuStatus.make(settings: settings, snapshot: snapshot, desiredState: .disconnected)
            check(status.title == (paired ? "Bluetooth is off, so the keyboard can’t be released" : "Bluetooth is off") &&
                  status.action == .enableBluetooth,
                  "Bluetooth off names a keyboard that is still paired here")
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
        {"selectedDisplay": {"identifier": "display-1", "name": "Display", "isBuiltIn": false},
         "selectedUSBHub": {"identifier": "hub-1", "name": "Hub", "manufacturer": "", "vendorID": 1, "productID": 2},
         "monitorInputs": {"displayIdentifier": "display-1", "thisMac": 19, "otherMac": 21},
         "shortcut": {"keyCode": 40, "modifiers": 6400}}
        """
        let decoded = try? JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        check(decoded?.selectedUSBHubs.map(\.identifier) == ["hub-1"], "legacy hub migrates to a group")
        check(decoded?.switchMainDisplay == true, "main-display preference defaults on")

        let encoded = decoded.flatMap { try? JSONEncoder().encode($0) }
        let roundTrip = encoded.flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) }
        check(roundTrip == decoded, "settings round-trip")
        check(decoded?.monitorConnections.count == 1 &&
              decoded?.monitorInputs(for: "display-1")?.otherMac == 21,
              "legacy hubs and inputs migrate to one connection")

        var swapped = decoded
        swapped?.setMonitorInputs(LearnedMonitorInputs(displayIdentifier: "display-2", thisMac: 21, otherMac: 19))
        check(swapped?.monitorInputs(for: "display-2")?.thisMac == 21 &&
              swapped?.monitorInputs(for: "display-1")?.thisMac == 19, "inputs are kept per connection")
        let legacyView = swapped.flatMap { try? JSONEncoder().encode($0) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        check((legacyView?["selectedUSBHubs"] as? [Any])?.count == 1 &&
              (legacyView?["monitorInputs"] as? [String: Any])?["displayIdentifier"] as? String == "display-1",
              "earlier builds read the hub group and the original display's inputs")
    }

    private static func checkMonitorIdentity() {
        let identity = MonitorIdentity(name: "BenQ", knownIdentifiers: ["old"])
        func display(_ identifier: String, _ name: String, builtIn: Bool = false) -> DisplayDescriptor {
            DisplayDescriptor(identifier: identifier, name: name, isBuiltIn: builtIn)
        }
        check(identity.identifier(among: [display("new", "BenQ"), display("old", "Renamed")]) == "old",
              "a known identity is preferred")
        check(identity.identifier(among: [display("new", "BenQ"), display("lg", "LG")]) == "new",
              "the only display with the monitor's name is a new connection")
        check(identity.identifier(among: [display("a", "BenQ"), display("b", "BenQ")]) == nil,
              "several displays with the monitor's name are ambiguous")
        check(identity.identifier(among: [display("built-in", "BenQ", builtIn: true)]) == nil,
              "built-in displays are never the monitor")
    }

    @MainActor
    private static func checkConnectionRecognition() async {
        var named = display("new-connection", builtIn: false, active: true, x: 0)
        named.name = "External"
        let system = CheckDisplayPrimarySystem(snapshots: [display("built-in", builtIn: true, active: true, x: -1440), named],
                                               mainIdentifier: "new-connection")
        let monitor = DisplayMonitor(configuredMonitor: MonitorIdentity(name: "External", knownIdentifiers: ["old"]),
                                     debounceInterval: 0, primaryDisplaySystem: system)
        check(monitor.start() && monitor.currentDisplayIdentifier == "new-connection",
              "the monitor is recognised through a new connection")
        monitor.stop()
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
        withInputs.setMonitorInputs(both!)
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

        var swappedCables = withInputs
        swappedCables.setMonitorInputs(LearnedMonitorInputs(displayIdentifier: "display-2", thisMac: 21, otherMac: nil))
        let afterSwap = MenuStatus.make(
            settings: swappedCables,
            snapshot: OwnershipSnapshot(keyboardState: .connectedLocal, ownershipReason: .none, monitorPresent: true,
                                        usbHubPresent: true, isBusy: false, errorMessage: nil),
            desiredState: nil,
            currentDisplayIdentifier: "display-2",
            monitorControlAvailable: true
        )
        check(afterSwap.monitorAction == .switchToOtherMac && swappedCables.monitorInputs(for: "display-2")?.otherMac == 19,
              "after a cable swap, this Mac's input completes the pair from the earlier connection")

        var unrelated = withInputs
        unrelated.setMonitorInputs(LearnedMonitorInputs(displayIdentifier: "display-3", thisMac: 15, otherMac: nil))
        check(unrelated.monitorInputs(for: "display-3")?.otherMac == nil, "an input outside the known pair is not completed")
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
    private static func checkDormantPairingRelease() async {
        let keyboard = CheckKeyboardController()
        keyboard.paired = true
        keyboard.bluetoothAvailability = .poweredOff
        let ownership = OwnershipController(keyboard: keyboard)
        ownership.start(monitorPresent: true, usbHubPresent: false)
        await ownership.waitForIdle()
        check(keyboard.releases == 0, "nothing is released while Bluetooth is off")
        keyboard.setAvailability(.poweredOn)
        await ownership.waitForIdle()
        check(keyboard.releases == 1 && !keyboard.paired,
              "a pairing left while Bluetooth was off is released when it comes back")

        let idle = CheckKeyboardController()
        idle.paired = true
        let away = OwnershipController(keyboard: idle)
        away.start(monitorPresent: false)
        await away.waitForIdle()
        check(idle.releases == 1 && !idle.paired, "a paired but disconnected keyboard is released")

        let owned = CheckKeyboardController()
        owned.paired = true
        let here = OwnershipController(keyboard: owned)
        here.start(monitorPresent: true, usbHubPresent: true)
        await here.waitForIdle()
        check(owned.releases == 0 && owned.state == .connectedLocal,
              "a paired keyboard is kept while the monitor shows this Mac")
    }

    @MainActor
    private static func checkClaimRetries() async {
        final class Keyboard: KeyboardControlling {
            var configuredKeyboard: KeyboardDescriptor? = KeyboardDescriptor(identifier: "k", name: "Keyboard")
            var state: KeyboardConnectionState = .disconnected
            var bluetoothAvailability: BluetoothAvailability = .poweredOn
            var onBluetoothAvailabilityChange: (() -> Void)?
            var lastError: String?
            var onStateChange: ((KeyboardConnectionState) -> Void)?
            var connectCount = 0
            var cancelCount = 0
            var failures = 0
            var blockNext = false
            var blocked: CheckedContinuation<Bool, Never>?
            var connectStartTimes: [UInt64] = []
            var connectDelayNanoseconds: UInt64 = 0
            var activeConnectCount = 0
            var maximumConcurrentConnectCount = 0

            func availableKeyboards() async -> [KeyboardDescriptor] { [] }
            func stop() {}
            func refreshState() {
                if state == .failed { state = .disconnected }
                onStateChange?(state)
            }
            func connect() async -> Bool {
                connectCount += 1
                connectStartTimes.append(DispatchTime.now().uptimeNanoseconds)
                activeConnectCount += 1
                maximumConcurrentConnectCount = max(maximumConcurrentConnectCount, activeConnectCount)
                defer { activeConnectCount -= 1 }
                state = .connecting
                onStateChange?(state)
                var succeeded = true
                if connectDelayNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: connectDelayNanoseconds)
                }
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

        let longDelay = AutomaticClaimRetryPolicy(
            fastRecoveryWindowNanoseconds: 120_000_000_000,
            minimumStartIntervalNanoseconds: 60_000_000_000,
            slowRetryDelaysNanoseconds: [60_000_000_000],
            releaseRetryDelaysNanoseconds: [1_000_000_000, 1_000_000_000]
        )

        // A failed claim must wait for its scheduled retry, not the 0.75 s USB-hub claim.
        let failing = Keyboard()
        failing.failures = 1
        let waiting = OwnershipController(keyboard: failing, claimRetryPolicy: longDelay)
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
        let immediateRetry = AutomaticClaimRetryPolicy(
            fastRecoveryWindowNanoseconds: 0,
            minimumStartIntervalNanoseconds: 0,
            slowRetryDelaysNanoseconds: [0],
            releaseRetryDelaysNanoseconds: [1_000_000_000, 1_000_000_000]
        )
        let finishing = OwnershipController(keyboard: exhausted, claimRetryPolicy: immediateRetry)
        finishing.start(monitorPresent: true, usbHubPresent: true)
        while exhausted.connectCount < 2 { await Task.yield() }
        await finishing.waitForIdle()
        check(exhausted.connectCount == 2 && !finishing.snapshot.isRetryingClaim, "retry loop ends after the last retry")

        let rapidFailures = Keyboard()
        rapidFailures.failures = 2
        rapidFailures.connectDelayNanoseconds = 40_000_000
        let fastPolicy = AutomaticClaimRetryPolicy(
            fastRecoveryWindowNanoseconds: 300_000_000,
            minimumStartIntervalNanoseconds: 20_000_000,
            slowRetryDelaysNanoseconds: [60_000_000],
            releaseRetryDelaysNanoseconds: [1_000_000_000, 1_000_000_000]
        )
        let fast = OwnershipController(keyboard: rapidFailures, claimRetryPolicy: fastPolicy)
        fast.start(monitorPresent: true, usbHubPresent: true)
        while rapidFailures.connectCount < 3 { await Task.yield() }
        await fast.waitForIdle()
        check(rapidFailures.connectCount == 3, "fast recovery retries ordinary failures consecutively")
        check(rapidFailures.connectStartTimes[1] - rapidFailures.connectStartTimes[0] < 100_000_000,
              "fast recovery adds no delay after an ordinary failed claim")
        check(rapidFailures.maximumConcurrentConnectCount == 1, "automatic claims remain single flight")

        let slowFailures = Keyboard()
        slowFailures.failures = 3
        let slowPolicy = AutomaticClaimRetryPolicy(
            fastRecoveryWindowNanoseconds: 0,
            minimumStartIntervalNanoseconds: 0,
            slowRetryDelaysNanoseconds: [20_000_000, 40_000_000],
            releaseRetryDelaysNanoseconds: [1_000_000_000, 1_000_000_000]
        )
        let slow = OwnershipController(keyboard: slowFailures, claimRetryPolicy: slowPolicy)
        slow.start(monitorPresent: true, usbHubPresent: true)
        while slowFailures.connectCount < 3 { await Task.yield() }
        await slow.waitForIdle()
        try? await Task.sleep(nanoseconds: 60_000_000)
        check(slowFailures.connectCount == 3, "slow backoff stops after its final retry")
        check(slowFailures.connectStartTimes[1] - slowFailures.connectStartTimes[0] >= 20_000_000,
              "first slow retry waits its configured delay")
        check(slowFailures.connectStartTimes[2] - slowFailures.connectStartTimes[1] >= 40_000_000,
              "second slow retry waits its configured delay")

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
        let rescheduling = OwnershipController(keyboard: stuckAgain, claimRetryPolicy: longDelay)
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
    var paired = false
    var isPaired: Bool { paired || state == .connectedLocal }
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
        paired = success
        state = success ? .connectedLocal : .failed
        onStateChange?(state)
        return success
    }
    func cancelConnect() {
        blockedClaim?.resume(returning: false)
        blockedClaim = nil
    }
    func disconnect() async -> Bool {
        releases += 1
        paired = false
        state = .disconnected
        onStateChange?(state)
        return true
    }
}

@MainActor
private final class CheckDisplayPrimarySystem: DisplayPrimarySystem {
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
