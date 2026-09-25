import XCTest
@testable import GetKbd

final class MenuStatusTests: XCTestCase {
    func testSetupNotFinished() {
        let status = MenuStatus.make(settings: .initial, snapshot: snapshot(), desiredState: nil)

        XCTAssertEqual(status, MenuStatus(title: "Setup isn’t finished", action: .finishSetup))
    }

    func testKeyboardConnectedOffersRelease() {
        let status = make(snapshot(keyboard: .connectedLocal, usbHub: true))

        XCTAssertEqual(status, MenuStatus(title: "Keyboard connected to this Mac", action: .release))
    }

    func testMonitorShowingOtherMacOffersNoAction() {
        let status = make(snapshot(keyboard: .disconnected, usbHub: false))

        XCTAssertEqual(status, MenuStatus(title: "Monitor is showing your other Mac", action: nil))
    }

    func testMonitorShowingThisMacWithoutKeyboardOffersGet() {
        let status = make(snapshot(keyboard: .disconnected, usbHub: true))

        XCTAssertEqual(status, MenuStatus(title: "Keyboard not connected", action: .get))
    }

    func testMonitorNotConnectedOffersGet() {
        let status = make(snapshot(keyboard: .disconnected, monitor: false, usbHub: false))

        XCTAssertEqual(status, MenuStatus(title: "Monitor not connected", action: .get))
    }

    func testOperationInProgressOffersNoAction() {
        XCTAssertEqual(make(snapshot(keyboard: .connecting)).action, nil)
        XCTAssertEqual(make(snapshot(keyboard: .disconnecting)).title, "Releasing keyboard…")
        XCTAssertEqual(make(snapshot(keyboard: .disconnected, busy: true), desired: .connected).action, nil)
    }

    func testFailureOffersRetry() {
        XCTAssertEqual(
            make(snapshot(keyboard: .failed), desired: .connected),
            MenuStatus(title: "Couldn’t connect the keyboard", action: .retry)
        )
        XCTAssertEqual(
            make(snapshot(keyboard: .failed), desired: .disconnected),
            MenuStatus(title: "Couldn’t release the keyboard", action: .retry)
        )
    }

    private func make(_ snapshot: OwnershipSnapshot, desired: DesiredKeyboardState? = nil) -> MenuStatus {
        MenuStatus.make(settings: configuredSettings, snapshot: snapshot, desiredState: desired)
    }

    private var configuredSettings: AppSettings {
        var settings = AppSettings.initial
        settings.selectedKeyboard = KeyboardDescriptor(identifier: "keyboard", name: "Keyboard")
        settings.selectedDisplay = DisplayDescriptor(identifier: "display", name: "Display", isBuiltIn: false)
        settings.selectedUSBHubs = [
            USBHubDescriptor(identifier: "hub", name: "Hub", manufacturer: "", vendorID: 1, productID: 2)
        ]
        return settings
    }

    private func snapshot(
        keyboard: KeyboardConnectionState = .disconnected,
        monitor: Bool = true,
        usbHub: Bool = true,
        busy: Bool = false
    ) -> OwnershipSnapshot {
        OwnershipSnapshot(
            keyboardState: keyboard,
            ownershipReason: .none,
            monitorPresent: monitor,
            usbHubPresent: usbHub,
            isBusy: busy,
            errorMessage: nil
        )
    }
}
