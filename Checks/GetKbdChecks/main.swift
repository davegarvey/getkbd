import Foundation

@main
struct GetKbdChecks {
    static func main() {
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

    private static func check(_ condition: Bool, _ name: String) {
        precondition(condition, "Check failed: \(name)")
    }
}
