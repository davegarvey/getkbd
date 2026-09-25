import XCTest
@testable import GetKbd

final class HubIdentificationTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let monitorUSB2 = hub("monitor-usb2")
    private let monitorUSB3 = hub("monitor-usb3")
    private let dock = hub("dock")
    private let stick = hub("stick")

    func testHubsThatLeaveAndReturnFormTheGroup() {
        var identification = HubIdentification(hubs: [dock, monitorUSB2, monitorUSB3], at: start)

        identification.observe([dock], at: start + 5)
        identification.tick(at: start + 7)
        XCTAssertEqual(identification.phase, .waitingForSwitchBack)

        identification.observe([dock, monitorUSB2, monitorUSB3], at: start + 15)
        identification.tick(at: start + 16)
        XCTAssertEqual(identification.phase, .waitingForSwitchBack)
        identification.tick(at: start + 17)

        XCTAssertEqual(identification.phase, .succeeded([monitorUSB2, monitorUSB3]))
    }

    func testHubsThatArriveAndLeaveFormTheGroup() {
        var identification = HubIdentification(hubs: [dock], at: start)

        identification.observe([dock, monitorUSB2], at: start + 5)
        identification.tick(at: start + 7)
        identification.observe([dock], at: start + 15)
        identification.tick(at: start + 17)

        XCTAssertEqual(identification.phase, .succeeded([monitorUSB2]))
    }

    func testHubThatChangesOnlyOnceIsExcluded() {
        var identification = HubIdentification(hubs: [dock, monitorUSB2], at: start)

        identification.observe([dock, monitorUSB2, stick], at: start + 2)
        identification.tick(at: start + 4)
        identification.observe([dock, stick], at: start + 6)
        identification.tick(at: start + 8)
        XCTAssertEqual(identification.phase, .waitingForSwitchBack)

        identification.observe([dock, monitorUSB2, stick], at: start + 12)
        identification.tick(at: start + 14)

        XCTAssertEqual(identification.phase, .succeeded([monitorUSB2]))
    }

    func testUnsettledFlapIsIgnored() {
        var identification = HubIdentification(hubs: [monitorUSB2], at: start)

        identification.observe([], at: start + 1)
        identification.observe([monitorUSB2], at: start + 1.5)
        identification.tick(at: start + 4)

        XCTAssertEqual(identification.phase, .waitingForFirstSwitch)
    }

    func testNoReturnTimesOut() {
        var identification = HubIdentification(hubs: [monitorUSB2], at: start)

        identification.observe([], at: start + 5)
        identification.tick(at: start + 7)
        identification.tick(at: start + HubIdentification.timeout)

        XCTAssertEqual(identification.phase, .timedOut)
    }
}

private func hub(_ identifier: String) -> USBHubDescriptor {
    USBHubDescriptor(identifier: identifier, name: identifier, manufacturer: "", vendorID: 1, productID: 2)
}
