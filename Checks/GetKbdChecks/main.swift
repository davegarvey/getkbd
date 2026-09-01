import Foundation

@main
struct GetKbdChecks {
    @MainActor
    static func main() async {
        runPureChecks()
        await runPeerIntegrationCheck()
        print("GetKbd checks passed.")
    }

    private static func runPureChecks() {
        check(PeerMessageValidation.isSupported(version: 1, kind: "status"), "supported peer message")
        check(!PeerMessageValidation.isSupported(version: 2, kind: "status"), "unsupported peer version")
        check(!PeerMessageValidation.isSupported(version: 1, kind: "remoteClaim"), "unsupported peer message")

        let hub = USBHubDescriptor(
            identifier: "hub-1",
            name: "Switch Hub",
            manufacturer: "Switch Co",
            vendorID: 1,
            productID: 2
        )

        let verified = HubTransitionAnalyzer.analyze(
            localBefore: [hub],
            localAfter: [],
            remoteBefore: [],
            remoteAfter: [hub]
        )
        check(verified.status == .verified && verified.hub == hub, "complementary hub transition")

        let unsafe = HubTransitionAnalyzer.analyze(
            localBefore: [],
            localAfter: [hub],
            remoteBefore: [],
            remoteAfter: [hub]
        )
        check(unsafe.status == .unsafe, "shared hub detection")

        let noSignal = HubTransitionAnalyzer.analyze(
            localBefore: [hub],
            localAfter: [],
            remoteBefore: [],
            remoteAfter: []
        )
        check(noSignal.status == .noSignal, "peer-unavailable fallback")

        let waitingForReturn = KVMTestAnalyzer.nextStatus(
            current: .waitingForFirstSwitch,
            baselineLocalConnected: true,
            baselineRemoteConnected: false,
            localConnected: false,
            remoteConnected: true
        )
        check(waitingForReturn == .waitingForReturn, "first KVM test direction")

        let passed = KVMTestAnalyzer.nextStatus(
            current: .waitingForReturn,
            baselineLocalConnected: true,
            baselineRemoteConnected: false,
            localConnected: true,
            remoteConnected: false
        )
        check(passed == .passed, "second KVM test direction")
    }

    @MainActor
    private static func runPeerIntegrationCheck() async {
        let defaultsA = UserDefaults(suiteName: "GetKbdChecks-A-\(UUID().uuidString)")!
        let defaultsB = UserDefaults(suiteName: "GetKbdChecks-B-\(UUID().uuidString)")!
        let first = PeerVerificationController(store: PeerStore(defaults: defaultsA))
        let second = PeerVerificationController(store: PeerStore(defaults: defaultsB))

        first.start()
        second.start()
        await waitUntil({
            first.hasDiscoveredPeer(withInstanceID: second.localInstanceID) &&
                second.hasDiscoveredPeer(withInstanceID: first.localInstanceID)
        }, name: "peer discovery")

        first.connectToDiscoveredPeer(withInstanceID: second.localInstanceID)
        await waitUntil({
            first.connectionState == .awaitingConfirmation &&
                second.connectionState == .awaitingConfirmation
        }, name: "peer handshake") {
            "first=\(first.connectionState), second=\(second.connectionState), first ID=\(first.localInstanceID), second ID=\(second.localInstanceID), first peers=\(first.discoveredPeerSummaries), second peers=\(second.discoveredPeerSummaries)"
        }
        check(first.pairingCode == second.pairingCode, "matching pairing codes")

        first.confirmPairing()
        second.confirmPairing()
        await waitUntil({ first.isPeerConnected && second.isPeerConnected }, name: "peer pairing")

        let keyboard = KeyboardDescriptor(identifier: "keyboard-1", name: "Shared Keyboard")
        let display = DisplayDescriptor(identifier: "display-1", name: "Shared Display", isBuiltIn: false)
        let hub = USBHubDescriptor(
            identifier: "hub-1",
            name: "Switch Hub",
            manufacturer: "Switch Co",
            vendorID: 1,
            productID: 2
        )
        var settings = AppSettings.initial
        settings.selectedKeyboard = keyboard
        settings.selectedDisplay = display
        settings.selectedUSBHub = hub
        settings.automaticSource = .usbHub

        let connected = OwnershipSnapshot(
            keyboardState: .connectedLocal,
            ownershipReason: .usbHub,
            monitorPresent: true,
            usbHubPresent: true,
            isBusy: false,
            errorMessage: nil
        )
        let disconnected = OwnershipSnapshot(
            keyboardState: .disconnected,
            ownershipReason: .none,
            monitorPresent: true,
            usbHubPresent: false,
            isBusy: false,
            errorMessage: nil
        )

        first.publishLocalStatus(settings: settings, snapshot: connected, hubs: [hub])
        second.publishLocalStatus(settings: settings, snapshot: disconnected, hubs: [])
        first.localHubsChanged([hub])
        second.localHubsChanged([])
        first.beginHubDetection(localHubs: [hub])
        await waitUntil({ second.verificationStatus == .listening }, name: "hub detection start")
        first.localHubsChanged([])
        second.localHubsChanged([hub])
        await waitUntil({
            first.verificationStatus == .verified && second.verificationStatus == .verified
        }, name: "hub verification")

        first.startKVMTest()
        await waitUntil({
            first.kvmTestStatus == .waitingForFirstSwitch &&
                second.kvmTestStatus == .waitingForFirstSwitch
        }, name: "KVM test start")

        first.publishLocalStatus(settings: settings, snapshot: disconnected, hubs: [])
        second.publishLocalStatus(settings: settings, snapshot: connected, hubs: [hub])
        await waitUntil({
            first.kvmTestStatus == .waitingForReturn &&
                second.kvmTestStatus == .waitingForReturn
        }, name: "KVM first direction")

        first.publishLocalStatus(settings: settings, snapshot: connected, hubs: [hub])
        second.publishLocalStatus(settings: settings, snapshot: disconnected, hubs: [])
        await waitUntil({ first.kvmTestStatus == .passed && second.kvmTestStatus == .passed }, name: "KVM test completion")

        first.stop()
        second.stop()
    }

    @MainActor
    private static func waitUntil(
        _ condition: () -> Bool,
        name: String,
        diagnostic: (() -> String)? = nil
    ) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let detail = diagnostic.map { " (\($0()))" } ?? ""
        preconditionFailure("Timed out waiting for \(name)\(detail)")
    }

    private static func check(_ condition: Bool, _ name: String) {
        precondition(condition, "Check failed: \(name)")
    }
}
