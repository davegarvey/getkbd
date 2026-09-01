import CryptoKit
import Foundation
import Network

enum PeerMessageValidation {
    static let supportedVersion = 1
    private static let supportedKinds: Set<String> = [
        "hello",
        "pairingConfirmation",
        "status",
        "hubDetectionStart",
        "hubSnapshot",
        "testStart"
    ]

    static func isSupported(version: Int, kind: String) -> Bool {
        version == supportedVersion && supportedKinds.contains(kind)
    }
}

struct HubTransitionAnalysis: Equatable, Sendable {
    let status: PeerVerificationStatus
    let hub: USBHubDescriptor?
}

enum HubTransitionAnalyzer {
    static func analyze(
        localBefore: [USBHubDescriptor],
        localAfter: [USBHubDescriptor],
        remoteBefore: [USBHubDescriptor],
        remoteAfter: [USBHubDescriptor]
    ) -> HubTransitionAnalysis {
        let localBeforeIDs = Set(localBefore.map(\.identifier))
        let localAfterIDs = Set(localAfter.map(\.identifier))
        let remoteBeforeIDs = Set(remoteBefore.map(\.identifier))
        let remoteAfterIDs = Set(remoteAfter.map(\.identifier))

        let currentlyShared = localAfterIDs.intersection(remoteAfterIDs)
        if let sharedID = currentlyShared.first {
            let hub = (localAfter + remoteAfter).first { $0.identifier == sharedID }
            return HubTransitionAnalysis(status: .unsafe, hub: hub)
        }

        let localChanges = localBeforeIDs.symmetricDifference(localAfterIDs)
        let remoteChanges = remoteBeforeIDs.symmetricDifference(remoteAfterIDs)

        guard localChanges.count == 1, remoteChanges.count == 1,
              localChanges == remoteChanges,
              let identifier = localChanges.first else {
            if localChanges.count > 1 || remoteChanges.count > 1 {
                return HubTransitionAnalysis(status: .ambiguous, hub: nil)
            }
            return HubTransitionAnalysis(status: .noSignal, hub: nil)
        }

        let hub = (localBefore + localAfter + remoteBefore + remoteAfter)
            .first { $0.identifier == identifier }
        return HubTransitionAnalysis(status: .verified, hub: hub)
    }
}

enum KVMTestAnalyzer {
    static func nextStatus(
        current: KVMTestStatus,
        baselineLocalConnected: Bool,
        baselineRemoteConnected: Bool,
        localConnected: Bool,
        remoteConnected: Bool
    ) -> KVMTestStatus {
        switch current {
        case .waitingForFirstSwitch:
            guard localConnected != baselineLocalConnected,
                  remoteConnected != baselineRemoteConnected,
                  localConnected != remoteConnected else {
                return current
            }
            return .waitingForReturn
        case .waitingForReturn:
            guard localConnected == baselineLocalConnected,
                  remoteConnected == baselineRemoteConnected else {
                return current
            }
            return .passed
        default:
            return current
        }
    }
}

@MainActor
final class PeerVerificationController {
    private static let protocolVersion = PeerMessageValidation.supportedVersion
    private static let serviceType = "_getkbd._tcp"
    private static let servicePrefix = "getkbd - "
    private static let hubEvaluationDelayNanoseconds: UInt64 = 250_000_000

    private enum MessageKind: String, Codable {
        case hello
        case pairingConfirmation
        case status
        case hubDetectionStart
        case hubSnapshot
        case testStart
    }

    private struct Message: Codable {
        let version: Int
        let kind: MessageKind
        let instanceID: String?
        let displayName: String?
        let nonce: String?
        let code: String?
        let sessionID: String?
        let hubs: [USBHubDescriptor]?
        let status: RuntimeStatus?
    }

    private struct Hello {
        let instanceID: String
        let displayName: String
        let nonce: String
    }

    private struct RuntimeStatus: Codable, Equatable {
        let selectedKeyboardIdentifier: String?
        let selectedDisplayIdentifier: String?
        let selectedUSBHubIdentifier: String?
        let keyboardState: String
        let keyboardConnected: Bool
        let monitorPresent: Bool
        let usbHubPresent: Bool
        let displayHandoffState: String
        let isReady: Bool
        let verificationStatus: PeerVerificationStatus
        let kvmTestStatus: KVMTestStatus
        let hubIdentifiers: [String]
    }

    private struct DiscoveredPeer {
        let identifier: String
        let name: String
        let endpoint: NWEndpoint
    }

    private let store: PeerStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var activeConnection: NWConnection?
    private var activeConnectionToken: UUID?
    private var receiveBuffer = Data()
    private var discoveredPeers: [DiscoveredPeer] = []
    private var remoteHello: Hello?
    private var localNonce: String?
    private var localPairConfirmed = false
    private var remotePairConfirmed = false
    private var localRuntimeStatus: RuntimeStatus?
    private var remoteRuntimeStatus: RuntimeStatus?
    private var localHubIdentifiers: Set<String> = []
    private var hubSessionID: String?
    private var localHubBaseline: [USBHubDescriptor]?
    private var localHubCurrent: [USBHubDescriptor]?
    private var remoteHubBaseline: [USBHubDescriptor]?
    private var remoteHubCurrent: [USBHubDescriptor]?
    private var hubEvaluationTask: Task<Void, Never>?
    private var testSessionID: String?
    private var testBaselineLocalConnected: Bool?
    private var testBaselineRemoteConnected: Bool?

    private(set) var connectionState: PeerConnectionState = .unavailable
    private(set) var pairingCode: String?
    private(set) var verificationStatus: PeerVerificationStatus
    private(set) var detectedHub: USBHubDescriptor?
    private(set) var kvmTestStatus: KVMTestStatus
    private(set) var lastMessage: String?

    var onChange: (() -> Void)?

    convenience init() {
        self.init(store: PeerStore())
    }

    init(store: PeerStore) {
        self.store = store
        verificationStatus = store.value.verificationStatus
        kvmTestStatus = store.value.kvmTestStatus
    }

    var isPaired: Bool {
        store.value.pairedPeerID != nil
    }

    var isPeerConnected: Bool {
        connectionState == .paired
    }

    var peerName: String? {
        remoteHello?.displayName ?? store.value.pairedPeerName ?? discoveredPeerName
    }

    var discoveredPeerName: String? {
        discoveredPeers.first?.name
    }

    var hasDiscoveredPeer: Bool {
        !discoveredPeers.isEmpty
    }

    func hasDiscoveredPeer(withInstanceID instanceID: String) -> Bool {
        let shortID = String(instanceID.prefix(Self.shortInstanceIDLength))
        return discoveredPeers.contains { $0.identifier == shortID }
    }

    var localInstanceID: String {
        store.value.instanceID
    }

    var discoveredPeerSummaries: [String] {
        discoveredPeers.map { "\($0.name) (\($0.identifier))" }
    }

    var peerStatusTitle: String {
        switch connectionState {
        case .unavailable:
            return isPaired ? "Other Mac unavailable" : "Other Mac not connected"
        case .discovered:
            return "Other Mac found"
        case .connecting:
            return "Connecting to Other Mac..."
        case .awaitingConfirmation:
            return "Confirm pairing on both Macs"
        case .paired:
            return "Other Mac connected"
        case .stale:
            return "Other Mac unavailable"
        }
    }

    var peerDetail: String {
        if let peerName {
            return "\(peerStatusTitle): \(peerName)"
        }
        return peerStatusTitle
    }

    var verificationTitle: String {
        verificationStatus.menuTitle
    }

    var kvmTestTitle: String {
        kvmTestStatus.menuTitle
    }

    var remoteReady: Bool {
        remoteRuntimeStatus?.isReady == true
    }

    var remoteKeyboardConnected: Bool? {
        remoteRuntimeStatus?.keyboardConnected
    }

    func start() {
        guard listener == nil, browser == nil else { return }

        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(
                name: localServiceName,
                type: Self.serviceType
            )
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    self?.listenerStateChanged(state)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated {
                    self?.accept(connection)
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            lastMessage = "Unable to advertise this Mac for setup verification."
        }

        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: .tcp
        )
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                self?.browserStateChanged(state)
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                self?.updateDiscoveredPeers(results)
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        activeConnection?.cancel()
        activeConnection = nil
        activeConnectionToken = nil
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
        connectionState = isPaired ? .stale : .unavailable
        notifyChange()
    }

    func connectToDiscoveredPeer() {
        connectToDiscoveredPeer(at: 0)
    }

    func connectToDiscoveredPeer(at index: Int) {
        guard discoveredPeers.indices.contains(index) else {
            lastMessage = "No other getkbd Mac was found on the local network."
            notifyChange()
            return
        }

        connect(to: discoveredPeers[index])
    }

    func connectToDiscoveredPeer(withInstanceID instanceID: String) {
        let shortID = String(instanceID.prefix(Self.shortInstanceIDLength))
        guard let peer = discoveredPeers.first(where: { $0.identifier == shortID }) else {
            lastMessage = "The selected getkbd Mac is no longer available."
            notifyChange()
            return
        }

        connect(to: peer)
    }

    func confirmPairing() {
        guard connectionState == .awaitingConfirmation,
              let pairingCode else { return }

        localPairConfirmed = true
        send(
            Message(
                version: Self.protocolVersion,
                kind: .pairingConfirmation,
                instanceID: store.value.instanceID,
                displayName: localDisplayName,
                nonce: nil,
                code: pairingCode,
                sessionID: nil,
                hubs: nil,
                status: nil
            )
        )
        completePairingIfReady()
        notifyChange()
    }

    func forgetPeer() {
        activeConnection?.cancel()
        activeConnection = nil
        activeConnectionToken = nil
        let preferences = PeerPreferences.initial(instanceID: store.value.instanceID)
        store.replace(preferences)
        connectionState = .unavailable
        pairingCode = nil
        remoteHello = nil
        verificationStatus = .unverified
        detectedHub = nil
        kvmTestStatus = .notStarted
        clearVerificationSession()
        notifyChange()
    }

    func publishLocalStatus(
        settings: AppSettings,
        snapshot: OwnershipSnapshot,
        hubs: [USBHubDescriptor]
    ) {
        localHubIdentifiers = Set(hubs.map(\.identifier))
        let status = RuntimeStatus(
            selectedKeyboardIdentifier: settings.selectedKeyboard?.identifier,
            selectedDisplayIdentifier: settings.selectedDisplay?.identifier,
            selectedUSBHubIdentifier: settings.selectedUSBHub?.identifier,
            keyboardState: snapshot.keyboardState.rawValue,
            keyboardConnected: snapshot.keyboardState == .connectedLocal,
            monitorPresent: snapshot.monitorPresent,
            usbHubPresent: snapshot.usbHubPresent,
            displayHandoffState: snapshot.displayHandoffState.rawValue,
            isReady: Self.isLocallyReady(settings),
            verificationStatus: verificationStatus,
            kvmTestStatus: kvmTestStatus,
            hubIdentifiers: Array(localHubIdentifiers).sorted()
        )
        localRuntimeStatus = status
        sendStatus()
        evaluateKVMTest()
    }

    func localHubsChanged(_ hubs: [USBHubDescriptor]) {
        localHubIdentifiers = Set(hubs.map(\.identifier))
        localHubCurrent = hubs
        if hubSessionID != nil {
            send(
                Message(
                    version: Self.protocolVersion,
                    kind: .hubSnapshot,
                    instanceID: store.value.instanceID,
                    displayName: localDisplayName,
                    nonce: nil,
                    code: nil,
                    sessionID: hubSessionID,
                    hubs: hubs,
                    status: nil
                )
            )
            scheduleHubVerificationEvaluation()
        }

        if var localRuntimeStatus {
            localRuntimeStatus = RuntimeStatus(
                selectedKeyboardIdentifier: localRuntimeStatus.selectedKeyboardIdentifier,
                selectedDisplayIdentifier: localRuntimeStatus.selectedDisplayIdentifier,
                selectedUSBHubIdentifier: localRuntimeStatus.selectedUSBHubIdentifier,
                keyboardState: localRuntimeStatus.keyboardState,
                keyboardConnected: localRuntimeStatus.keyboardConnected,
                monitorPresent: localRuntimeStatus.monitorPresent,
                usbHubPresent: localRuntimeStatus.usbHubPresent,
                displayHandoffState: localRuntimeStatus.displayHandoffState,
                isReady: localRuntimeStatus.isReady,
                verificationStatus: localRuntimeStatus.verificationStatus,
                kvmTestStatus: localRuntimeStatus.kvmTestStatus,
                hubIdentifiers: Array(localHubIdentifiers).sorted()
            )
            sendStatus()
        }
    }

    func beginHubDetection(localHubs: [USBHubDescriptor]) {
        guard isPeerConnected else {
            setVerificationStatus(.unavailable, message: "Pair the other Mac to verify this input switch.")
            return
        }

        let sessionID = UUID().uuidString
        hubSessionID = sessionID
        localHubBaseline = localHubs
        localHubCurrent = localHubs
        remoteHubBaseline = nil
        remoteHubCurrent = nil
        detectedHub = nil
        setVerificationStatus(.listening, message: "Change the monitor input to the other Mac.")

        send(
            Message(
                version: Self.protocolVersion,
                kind: .hubDetectionStart,
                instanceID: store.value.instanceID,
                displayName: localDisplayName,
                nonce: nil,
                code: nil,
                sessionID: sessionID,
                hubs: localHubs,
                status: nil
            )
        )
        sendHubSnapshot(localHubs)
    }

    func finishHubDetection() {
        guard verificationStatus == .listening else { return }
        clearVerificationSession()
        setVerificationStatus(.noSignal, message: "No complementary USB hub transition was detected.")
    }

    func startKVMTest() {
        guard isPeerConnected else {
            setTestStatus(.failed, message: "Pair the other Mac before testing the handoff.")
            return
        }
        guard let localRuntimeStatus,
              let remoteRuntimeStatus else {
            setTestStatus(.failed, message: "Both Macs must be ready before testing the handoff.")
            return
        }
        guard localRuntimeStatus.isReady,
              remoteRuntimeStatus.isReady else {
            setTestStatus(.failed, message: "Both Macs must be ready before testing the handoff.")
            return
        }
        guard localRuntimeStatus.keyboardConnected != remoteRuntimeStatus.keyboardConnected else {
            setTestStatus(.failed, message: "One Mac must currently own the keyboard before testing.")
            return
        }

        let sessionID = UUID().uuidString
        testSessionID = sessionID
        testBaselineLocalConnected = localRuntimeStatus.keyboardConnected
        testBaselineRemoteConnected = remoteRuntimeStatus.keyboardConnected
        setTestStatus(.waitingForFirstSwitch, message: "Change the monitor input to the other Mac.")
        send(
            Message(
                version: Self.protocolVersion,
                kind: .testStart,
                instanceID: store.value.instanceID,
                displayName: localDisplayName,
                nonce: nil,
                code: nil,
                sessionID: sessionID,
                hubs: nil,
                status: nil
            )
        )
    }

    func skipKVMTest() {
        testSessionID = nil
        setTestStatus(.skipped, message: "The handoff is configured but has not been verified.")
    }

    private var localDisplayName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    private static let shortInstanceIDLength = 8

    private var localServiceName: String {
        let cleanName = localDisplayName
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
            .replacingOccurrences(of: "\n", with: " ")
        let suffix = " [\(String(store.value.instanceID.prefix(Self.shortInstanceIDLength)))]"
        let base = "\(Self.servicePrefix)\(cleanName)"
        let availableBaseLength = max(1, 63 - suffix.count)
        return String(base.prefix(availableBaseLength)) + suffix
    }

    private func listenerStateChanged(_ state: NWListener.State) {
        if case .failed = state {
            lastMessage = "Other Macs cannot discover this Mac for setup verification."
            notifyChange()
        }
    }

    private func browserStateChanged(_ state: NWBrowser.State) {
        if case .failed = state {
            lastMessage = "Unable to find the other Mac on the local network."
            notifyChange()
        }
    }

    private func updateDiscoveredPeers(_ results: Set<NWBrowser.Result>) {
        discoveredPeers = results.compactMap { result in
            guard case let .service(name, _, _, _) = result.endpoint else {
                return nil
            }

            let details = Self.peerDetails(from: name)
            guard details.identifier != String(store.value.instanceID.prefix(Self.shortInstanceIDLength)) else {
                return nil
            }
            return DiscoveredPeer(
                identifier: details.identifier,
                name: details.name,
                endpoint: result.endpoint
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if activeConnection == nil {
            if let pairedPeerID = store.value.pairedPeerID,
               let peer = discoveredPeers.first(where: {
                   $0.identifier == String(pairedPeerID.prefix(Self.shortInstanceIDLength))
               }) {
                connect(to: peer)
            } else if !discoveredPeers.isEmpty {
                connectionState = .discovered
                notifyChange()
            }
        }
    }

    private static func peerDetails(from serviceName: String) -> (identifier: String, name: String) {
        guard serviceName.hasPrefix(Self.servicePrefix),
              let openingBracket = serviceName.lastIndex(of: "["),
              serviceName.last == "]" else {
            return (serviceName, serviceName)
        }

        let identifier = String(serviceName[serviceName.index(after: openingBracket)..<serviceName.index(before: serviceName.endIndex)])
        let nameEnd = serviceName.index(before: openingBracket)
        let name = String(serviceName[..<nameEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (identifier, name.isEmpty ? "Other Mac" : name)
    }

    private func accept(_ connection: NWConnection) {
        if let activeConnection {
            activeConnection.cancel()
        }
        attach(connection, expectedPeerID: nil, expectedPeerName: nil)
    }

    private func connect(to peer: DiscoveredPeer) {
        activeConnection?.cancel()
        connectionState = .connecting
        lastMessage = nil
        attach(
            NWConnection(to: peer.endpoint, using: .tcp),
            expectedPeerID: peer.identifier,
            expectedPeerName: peer.name
        )
        notifyChange()
    }

    private func attach(
        _ connection: NWConnection,
        expectedPeerID: String?,
        expectedPeerName: String?
    ) {
        let token = UUID()
        activeConnection = connection
        activeConnectionToken = token
        receiveBuffer.removeAll()
        remoteHello = nil
        localNonce = UUID().uuidString
        pairingCode = nil
        localPairConfirmed = false
        remotePairConfirmed = false

        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                self?.connectionStateChanged(
                    state,
                    token: token,
                    expectedPeerID: expectedPeerID,
                    expectedPeerName: expectedPeerName
                )
            }
        }
        connection.start(queue: .main)
    }

    private func connectionStateChanged(
        _ state: NWConnection.State,
        token: UUID,
        expectedPeerID: String?,
        expectedPeerName: String?
    ) {
        guard activeConnectionToken == token else { return }

        switch state {
        case .ready:
            sendHello()
            receiveNext(on: activeConnection, token: token)
        case .failed, .cancelled:
            connectionLost(token: token, expectedPeerID: expectedPeerID, expectedPeerName: expectedPeerName)
        default:
            break
        }
    }

    private func connectionLost(token: UUID, expectedPeerID: String?, expectedPeerName: String?) {
        guard activeConnectionToken == token else { return }
        activeConnection = nil
        activeConnectionToken = nil
        remoteHello = nil
        pairingCode = nil
        localPairConfirmed = false
        remotePairConfirmed = false
        if let expectedPeerID,
           store.value.pairedPeerID == expectedPeerID || store.value.pairedPeerID != nil {
            connectionState = .stale
        } else {
            connectionState = .unavailable
        }
        if isPaired {
            let message = verificationStatus == .listening
                ? "The other Mac became unavailable during detection."
                : "The other Mac is unavailable; input verification is stale."
            setVerificationStatus(.unavailable, message: message)
        }
        if testSessionID != nil {
            setTestStatus(.failed, message: "The other Mac became unavailable during the handoff test.")
        }
        _ = expectedPeerName
        notifyChange()
    }

    private func sendHello() {
        guard let localNonce else { return }
        send(
            Message(
                version: Self.protocolVersion,
                kind: .hello,
                instanceID: store.value.instanceID,
                displayName: localDisplayName,
                nonce: localNonce,
                code: nil,
                sessionID: nil,
                hubs: nil,
                status: nil
            )
        )
    }

    private func receiveNext(on connection: NWConnection?, token: UUID) {
        guard let connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, self.activeConnectionToken == token else { return }

                if let data {
                    self.receiveBuffer.append(data)
                    self.processReceivedMessages()
                }

                if isComplete || error != nil {
                    self.connectionLost(token: token, expectedPeerID: nil, expectedPeerName: nil)
                } else {
                    self.receiveNext(on: connection, token: token)
                }
            }
        }
    }

    private func processReceivedMessages() {
        while let newline = receiveBuffer.firstIndex(of: 0x0A) {
            let line = receiveBuffer.prefix(upTo: newline)
            receiveBuffer.removeSubrange(...newline)
            guard let message = try? decoder.decode(Message.self, from: line) else {
                lastMessage = "The other Mac sent an invalid verification message."
                continue
            }
            handle(message)
        }
    }

    private func handle(_ message: Message) {
        guard PeerMessageValidation.isSupported(
            version: message.version,
            kind: message.kind.rawValue
        ) else {
            lastMessage = "The other Mac is using an incompatible getkbd version."
            return
        }

        switch message.kind {
        case .hello:
            handleHello(message)
        case .pairingConfirmation:
            handlePairingConfirmation(message)
        case .status:
            guard let status = message.status else { return }
            remoteRuntimeStatus = status
            evaluateKVMTest()
            notifyChange()
        case .hubDetectionStart:
            guard let sessionID = message.sessionID,
                  let hubs = message.hubs else { return }
            let isNewSession = hubSessionID != sessionID
            if isNewSession {
                hubSessionID = sessionID
                localHubBaseline = localHubCurrent
                remoteHubBaseline = hubs
                remoteHubCurrent = hubs
                setVerificationStatus(.listening, message: "Change the monitor input to the other Mac.")
            } else {
                remoteHubBaseline = hubs
                remoteHubCurrent = hubs
            }
            if isNewSession {
                send(
                    Message(
                        version: Self.protocolVersion,
                        kind: .hubDetectionStart,
                        instanceID: store.value.instanceID,
                        displayName: localDisplayName,
                        nonce: nil,
                        code: nil,
                        sessionID: sessionID,
                        hubs: localHubCurrent ?? [],
                        status: nil
                    )
                )
            }
            sendHubSnapshot(localHubCurrent ?? [])
        scheduleHubVerificationEvaluation()
        case .hubSnapshot:
            guard message.sessionID == hubSessionID,
                  let hubs = message.hubs else { return }
            remoteHubCurrent = hubs
            scheduleHubVerificationEvaluation()
        case .testStart:
            guard let sessionID = message.sessionID else { return }
            guard verificationStatus == .verified else {
                setTestStatus(.failed, message: "This Mac must finish input-signal verification before testing the handoff.")
                return
            }
            testSessionID = sessionID
            if let localRuntimeStatus, let remoteRuntimeStatus {
                testBaselineLocalConnected = localRuntimeStatus.keyboardConnected
                testBaselineRemoteConnected = remoteRuntimeStatus.keyboardConnected
            }
            setTestStatus(.waitingForFirstSwitch, message: "Change the monitor input to the other Mac.")
            evaluateKVMTest()
        }
    }

    private func handleHello(_ message: Message) {
        guard let instanceID = message.instanceID,
              let displayName = message.displayName,
              let nonce = message.nonce else {
            lastMessage = "The other Mac could not identify itself."
            return
        }

        remoteHello = Hello(instanceID: instanceID, displayName: displayName, nonce: nonce)

        if let pairedPeerID = store.value.pairedPeerID, pairedPeerID != instanceID {
            lastMessage = "A different Mac is already paired. Forget the current pairing before choosing another."
            activeConnection?.cancel()
            return
        }

        if let pairedPeerID = store.value.pairedPeerID, pairedPeerID == instanceID {
            connectionState = .paired
            pairingCode = nil
            localPairConfirmed = true
            remotePairConfirmed = true
            sendStatus()
            notifyChange()
            return
        }

        guard let localNonce else { return }
        pairingCode = Self.pairingCode(localNonce: localNonce, remoteNonce: nonce)
        connectionState = .awaitingConfirmation
        localPairConfirmed = false
        remotePairConfirmed = false
        notifyChange()
    }

    private func handlePairingConfirmation(_ message: Message) {
        guard connectionState == .awaitingConfirmation,
              let code = message.code,
              code == pairingCode else {
            lastMessage = "The pairing code did not match."
            return
        }

        remotePairConfirmed = true
        completePairingIfReady()
    }

    private func completePairingIfReady() {
        guard localPairConfirmed, remotePairConfirmed,
              let remoteHello else { return }

        var preferences = store.value
        preferences.pairedPeerID = remoteHello.instanceID
        preferences.pairedPeerName = remoteHello.displayName
        preferences.verificationStatus = verificationStatus
        preferences.kvmTestStatus = kvmTestStatus
        store.replace(preferences)
        connectionState = .paired
        pairingCode = nil
        lastMessage = "Paired with \(remoteHello.displayName)."
        sendStatus()
        notifyChange()
    }

    private func sendStatus() {
        guard let localRuntimeStatus else { return }
        send(
            Message(
                version: Self.protocolVersion,
                kind: .status,
                instanceID: store.value.instanceID,
                displayName: localDisplayName,
                nonce: nil,
                code: nil,
                sessionID: nil,
                hubs: nil,
                status: localRuntimeStatus
            )
        )
    }

    private func sendHubSnapshot(_ hubs: [USBHubDescriptor]) {
        guard let hubSessionID else { return }
        send(
            Message(
                version: Self.protocolVersion,
                kind: .hubSnapshot,
                instanceID: store.value.instanceID,
                displayName: localDisplayName,
                nonce: nil,
                code: nil,
                sessionID: hubSessionID,
                hubs: hubs,
                status: nil
            )
        )
    }

    private func evaluateHubVerification() {
        guard let localHubBaseline,
              let localHubCurrent,
              let remoteHubBaseline,
              let remoteHubCurrent else { return }

        let result = HubTransitionAnalyzer.analyze(
            localBefore: localHubBaseline,
            localAfter: localHubCurrent,
            remoteBefore: remoteHubBaseline,
            remoteAfter: remoteHubCurrent
        )

        guard result.status != .noSignal else { return }
        detectedHub = result.hub
        switch result.status {
        case .verified:
            setVerificationStatus(.verified, message: "The USB connection follows the monitor input.")
        case .unsafe:
            setVerificationStatus(.unsafe, message: "Both Macs see this USB hub. Automatic switching is unsafe.")
        case .ambiguous:
            setVerificationStatus(.ambiguous, message: "Several USB hubs changed. Select one manually.")
        default:
            break
        }
        clearVerificationSession()
    }

    private func scheduleHubVerificationEvaluation() {
        hubEvaluationTask?.cancel()
        hubEvaluationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.hubEvaluationDelayNanoseconds)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.hubEvaluationTask = nil
            self.evaluateHubVerification()
        }
    }

    private func evaluateKVMTest() {
        guard testSessionID != nil,
              let localRuntimeStatus,
              let remoteRuntimeStatus else { return }

        if localRuntimeStatus.keyboardState == KeyboardConnectionState.failed.rawValue ||
            remoteRuntimeStatus.keyboardState == KeyboardConnectionState.failed.rawValue {
            setTestStatus(.failed, message: "A keyboard handoff failed. Try the test again.")
            return
        }

        guard let baselineLocal = testBaselineLocalConnected,
              let baselineRemote = testBaselineRemoteConnected else {
            testBaselineLocalConnected = localRuntimeStatus.keyboardConnected
            testBaselineRemoteConnected = remoteRuntimeStatus.keyboardConnected
            return
        }

        let nextStatus = KVMTestAnalyzer.nextStatus(
            current: kvmTestStatus,
            baselineLocalConnected: baselineLocal,
            baselineRemoteConnected: baselineRemote,
            localConnected: localRuntimeStatus.keyboardConnected,
            remoteConnected: remoteRuntimeStatus.keyboardConnected
        )
        guard nextStatus != kvmTestStatus else { return }

        if nextStatus == .passed {
            testSessionID = nil
            setTestStatus(.passed, message: "Both directions completed successfully.")
        } else {
            setTestStatus(.waitingForReturn, message: "Switch the monitor input back to finish the test.")
        }
    }

    private func send(_ message: Message) {
        guard let connection = activeConnection,
              let data = try? encoder.encode(message) else { return }

        var framed = data
        framed.append(0x0A)
        connection.send(content: framed, completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            MainActor.assumeIsolated {
                self?.lastMessage = "Peer communication failed: \(error.localizedDescription)"
                self?.notifyChange()
            }
        })
    }

    private func setVerificationStatus(_ status: PeerVerificationStatus, message: String?) {
        verificationStatus = status
        detectedHub = status == .verified ? detectedHub : nil
        var preferences = store.value
        preferences.verificationStatus = status
        store.replace(preferences)
        lastMessage = message
        updateLocalRuntimeStatusMetadata()
        sendStatus()
        notifyChange()
    }

    private func setTestStatus(_ status: KVMTestStatus, message: String?) {
        kvmTestStatus = status
        var preferences = store.value
        preferences.kvmTestStatus = status
        store.replace(preferences)
        lastMessage = message
        updateLocalRuntimeStatusMetadata()
        sendStatus()
        notifyChange()
    }

    private func updateLocalRuntimeStatusMetadata() {
        guard let localRuntimeStatus else { return }
        self.localRuntimeStatus = RuntimeStatus(
            selectedKeyboardIdentifier: localRuntimeStatus.selectedKeyboardIdentifier,
            selectedDisplayIdentifier: localRuntimeStatus.selectedDisplayIdentifier,
            selectedUSBHubIdentifier: localRuntimeStatus.selectedUSBHubIdentifier,
            keyboardState: localRuntimeStatus.keyboardState,
            keyboardConnected: localRuntimeStatus.keyboardConnected,
            monitorPresent: localRuntimeStatus.monitorPresent,
            usbHubPresent: localRuntimeStatus.usbHubPresent,
            displayHandoffState: localRuntimeStatus.displayHandoffState,
            isReady: localRuntimeStatus.isReady,
            verificationStatus: verificationStatus,
            kvmTestStatus: kvmTestStatus,
            hubIdentifiers: localRuntimeStatus.hubIdentifiers
        )
    }

    private func clearVerificationSession() {
        hubEvaluationTask?.cancel()
        hubEvaluationTask = nil
        hubSessionID = nil
        localHubBaseline = nil
        localHubCurrent = nil
        remoteHubBaseline = nil
        remoteHubCurrent = nil
    }

    private func notifyChange() {
        onChange?()
    }

    private static func isLocallyReady(_ settings: AppSettings) -> Bool {
        guard settings.selectedKeyboard != nil else { return false }
        switch settings.automaticSource {
        case .monitor:
            return settings.selectedDisplay != nil
        case .usbHub:
            return settings.selectedDisplay != nil && settings.selectedUSBHub != nil
        case .off:
            return true
        }
    }

    private static func pairingCode(localNonce: String, remoteNonce: String) -> String {
        let input = [localNonce, remoteNonce].sorted().joined(separator: "|")
        let digest = SHA256.hash(data: Data(input.utf8))
        let value = digest.prefix(4).reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        return String(format: "%06u", value % 1_000_000)
    }
}
