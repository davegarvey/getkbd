import Foundation

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

        checkSettingsMigration()
        checkMenuStatus(settings)
        checkHubIdentification(hub)
        checkMonitorInputs(settings)
        await checkMonitorInputLearner()

        print("GetKbd checks passed.")
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

    private static func check(_ condition: Bool, _ name: String) {
        precondition(condition, "Check failed: \(name)")
    }
}
