import XCTest
@testable import GetKbd

final class AppSettingsTests: XCTestCase {
    func testLegacySettingsMigrate() throws {
        let json = """
        {
          "selectedKeyboard": {"identifier": "keyboard", "name": "Keyboard"},
          "selectedDisplay": {"identifier": "display", "name": "Display", "isBuiltIn": false},
          "selectedUSBHub": {"identifier": "hub", "name": "Hub", "manufacturer": "", "vendorID": 1, "productID": 2},
          "shortcut": {"keyCode": 40, "modifiers": 6400},
          "launchAtLogin": false
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.selectedUSBHubs.map(\.identifier), ["hub"])
        XCTAssertTrue(settings.switchMainDisplay)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertFalse(settings.needsOnboarding)
    }

    func testRoundTripKeepsGroupAndWritesLegacyHub() throws {
        var settings = AppSettings.initial
        settings.selectedUSBHubs = [
            USBHubDescriptor(identifier: "hub-a", name: "A", manufacturer: "", vendorID: 1, productID: 2),
            USBHubDescriptor(identifier: "hub-b", name: "B", manufacturer: "", vendorID: 1, productID: 3)
        ]
        settings.switchMainDisplay = false

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let legacy = object?["selectedUSBHub"] as? [String: Any]

        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(legacy?["identifier"] as? String, "hub-a")
    }

    func testInitialSettingsEnableMainDisplaySwitching() {
        XCTAssertTrue(AppSettings.initial.switchMainDisplay)
        XCTAssertTrue(AppSettings.initial.needsOnboarding)
    }
}
