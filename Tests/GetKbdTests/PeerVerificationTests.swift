import XCTest
@testable import GetKbd

final class PeerVerificationTests: XCTestCase {
    func testPeerMessageValidationRejectsUnknownVersionsAndKinds() {
        XCTAssertTrue(PeerMessageValidation.isSupported(version: 1, kind: "status"))
        XCTAssertFalse(PeerMessageValidation.isSupported(version: 2, kind: "status"))
        XCTAssertFalse(PeerMessageValidation.isSupported(version: 1, kind: "remoteClaim"))
    }

    func testComplementaryHubTransitionIsVerified() {
        let hub = USBHubDescriptor(
            identifier: "hub-1",
            name: "Switch Hub",
            manufacturer: "Switch Co",
            vendorID: 1,
            productID: 2
        )

        let result = HubTransitionAnalyzer.analyze(
            localBefore: [hub],
            localAfter: [],
            remoteBefore: [],
            remoteAfter: [hub]
        )

        XCTAssertEqual(result.status, .verified)
        XCTAssertEqual(result.hub, hub)
    }

    func testSharedHubIsUnsafe() {
        let hub = USBHubDescriptor(
            identifier: "hub-1",
            name: "Switch Hub",
            manufacturer: "Switch Co",
            vendorID: 1,
            productID: 2
        )

        let result = HubTransitionAnalyzer.analyze(
            localBefore: [],
            localAfter: [hub],
            remoteBefore: [],
            remoteAfter: [hub]
        )

        XCTAssertEqual(result.status, .unsafe)
        XCTAssertEqual(result.hub, hub)
    }

    func testMultipleChangesAreAmbiguous() {
        let firstHub = USBHubDescriptor(
            identifier: "hub-1",
            name: "First Hub",
            manufacturer: "Switch Co",
            vendorID: 1,
            productID: 2
        )
        let secondHub = USBHubDescriptor(
            identifier: "hub-2",
            name: "Second Hub",
            manufacturer: "Switch Co",
            vendorID: 1,
            productID: 3
        )

        let result = HubTransitionAnalyzer.analyze(
            localBefore: [firstHub],
            localAfter: [secondHub],
            remoteBefore: [secondHub],
            remoteAfter: [firstHub]
        )

        XCTAssertEqual(result.status, .ambiguous)
        XCTAssertNil(result.hub)
    }

    func testNoHubChangeReportsNoSignal() {
        let hub = USBHubDescriptor(
            identifier: "hub-1",
            name: "Switch Hub",
            manufacturer: "Switch Co",
            vendorID: 1,
            productID: 2
        )

        let result = HubTransitionAnalyzer.analyze(
            localBefore: [hub],
            localAfter: [hub],
            remoteBefore: [],
            remoteAfter: []
        )

        XCTAssertEqual(result.status, .noSignal)
        XCTAssertNil(result.hub)
    }

    func testLocalOnlyObservationDoesNotClaimPeerVerification() {
        let hub = USBHubDescriptor(
            identifier: "hub-1",
            name: "Switch Hub",
            manufacturer: "Switch Co",
            vendorID: 1,
            productID: 2
        )

        let result = HubTransitionAnalyzer.analyze(
            localBefore: [hub],
            localAfter: [],
            remoteBefore: [],
            remoteAfter: []
        )

        XCTAssertEqual(result.status, .noSignal)
    }

    func testKVMTestRequiresBothDirectionsToPass() {
        XCTAssertEqual(
            KVMTestAnalyzer.nextStatus(
                current: .waitingForFirstSwitch,
                baselineLocalConnected: true,
                baselineRemoteConnected: false,
                localConnected: false,
                remoteConnected: true
            ),
            .waitingForReturn
        )
        XCTAssertEqual(
            KVMTestAnalyzer.nextStatus(
                current: .waitingForReturn,
                baselineLocalConnected: true,
                baselineRemoteConnected: false,
                localConnected: true,
                remoteConnected: false
            ),
            .passed
        )
    }

    func testKVMTestDoesNotPassUntilTheSecondDirectionReturnsToBaseline() {
        XCTAssertEqual(
            KVMTestAnalyzer.nextStatus(
                current: .waitingForReturn,
                baselineLocalConnected: true,
                baselineRemoteConnected: false,
                localConnected: false,
                remoteConnected: true
            ),
            .waitingForReturn
        )
    }

    @MainActor
    func testHubDetectionReportsPeerUnavailableWithoutBlockingLocalSetup() {
        let defaults = UserDefaults(suiteName: "PeerVerificationTests-\(UUID().uuidString)")!
        let controller = PeerVerificationController(store: PeerStore(defaults: defaults))

        controller.beginHubDetection(localHubs: [])

        XCTAssertEqual(controller.verificationStatus, .unavailable)
    }
}
