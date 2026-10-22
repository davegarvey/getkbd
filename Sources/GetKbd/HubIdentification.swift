import Foundation

/// Identifies the monitor's USB hub group from a switch to the other Mac and back.
///
/// A hub belongs to the group when it changes from its baseline state in one settled
/// snapshot and returns to that state in a later one. Hubs that change only once, such
/// as a device plugged in partway through, are excluded.
struct HubIdentification {
    enum Phase: Equatable {
        case waitingForFirstSwitch
        case waitingForSwitchBack
        case succeeded([USBHubDescriptor])
        case timedOut
    }

    static let settleInterval: TimeInterval = 2
    static let timeout: TimeInterval = 120

    private(set) var phase: Phase = .waitingForFirstSwitch
    /// When the hubs first changed from the baseline, or nil while none has.
    private(set) var firstChangeAt: Date?

    private let timeout: TimeInterval?
    private let baseline: [String: USBHubDescriptor]
    private let startedAt: Date
    private var current: [String: USBHubDescriptor]
    private var observedHubs: [String: USBHubDescriptor]
    private var lastChangeAt: Date
    private var hasUnsettledChange = false
    private var changedSinceBaseline = Set<String>()

    /// A nil timeout waits for the switch indefinitely.
    init(hubs: [USBHubDescriptor], at date: Date, timeout: TimeInterval? = Self.timeout) {
        self.timeout = timeout
        baseline = Self.keyed(hubs)
        current = baseline
        observedHubs = baseline
        startedAt = date
        lastChangeAt = date
    }

    var isFinished: Bool {
        switch phase {
        case .succeeded, .timedOut: return true
        case .waitingForFirstSwitch, .waitingForSwitchBack: return false
        }
    }

    mutating func observe(_ hubs: [USBHubDescriptor], at date: Date) {
        guard !isFinished else { return }
        let keyed = Self.keyed(hubs)
        guard Set(keyed.keys) != Set(current.keys) else { return }
        observedHubs.merge(keyed, uniquingKeysWith: { _, latest in latest })
        current = keyed
        lastChangeAt = date
        firstChangeAt = firstChangeAt ?? date
        hasUnsettledChange = true
    }

    mutating func tick(at date: Date) {
        guard !isFinished else { return }

        if hasUnsettledChange, date.timeIntervalSince(lastChangeAt) >= Self.settleInterval {
            hasUnsettledChange = false
            evaluateSettledSnapshot()
            if isFinished { return }
        }

        if let timeout, date.timeIntervalSince(startedAt) >= timeout {
            phase = .timedOut
        }
    }

    private mutating func evaluateSettledSnapshot() {
        let differing = Set(baseline.keys).symmetricDifference(current.keys)
        changedSinceBaseline.formUnion(differing)

        let returned = changedSinceBaseline.subtracting(differing)
        guard returned.isEmpty else {
            let descriptors = returned
                .compactMap { observedHubs[$0] }
                .sorted { $0.identifier < $1.identifier }
            phase = .succeeded(descriptors)
            return
        }

        phase = changedSinceBaseline.isEmpty ? .waitingForFirstSwitch : .waitingForSwitchBack
    }

    private static func keyed(_ hubs: [USBHubDescriptor]) -> [String: USBHubDescriptor] {
        Dictionary(hubs.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Learns the hub group of a monitor connection that has none, such as after the user
/// changes cables, from the next switch to the other Mac and back.
@MainActor
final class ConnectionHubLearner {
    /// A switch that has not come back by then is discarded, so that a hub plugged in
    /// now and removed much later is not mistaken for the monitor's.
    static let switchBackLimit: TimeInterval = 120

    var onLearned: ((_ hubs: [USBHubDescriptor], _ displayIdentifier: String) -> Void)?

    private(set) var displayIdentifier: String?
    private var identification: HubIdentification?
    private var task: Task<Void, Never>?
    private var currentHubs: () -> [USBHubDescriptor] = { [] }

    /// Starts learning for a connection unless it is already being learned.
    func learn(displayIdentifier: String, hubs: @escaping () -> [USBHubDescriptor]) {
        guard displayIdentifier != self.displayIdentifier else { return }
        cancel()
        self.displayIdentifier = displayIdentifier
        currentHubs = hubs
        identification = HubIdentification(hubs: hubs(), at: Date(), timeout: nil)
        GetKbdLog.event("monitor.connection.learning", displayIdentifier)
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled, let self else { return }
                self.tick(at: Date())
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        identification = nil
        displayIdentifier = nil
    }

    func tick(at date: Date) {
        guard var identification, let displayIdentifier else { return }
        identification.observe(currentHubs(), at: date)
        identification.tick(at: date)

        if case .succeeded(let hubs) = identification.phase, !hubs.isEmpty {
            cancel()
            GetKbdLog.event("monitor.connection.learned", hubs.map(\.identifier).joined(separator: ", "))
            onLearned?(hubs, displayIdentifier)
            return
        }

        if identification.isFinished ||
            identification.firstChangeAt.map({ date.timeIntervalSince($0) >= Self.switchBackLimit }) == true {
            identification = HubIdentification(hubs: currentHubs(), at: date, timeout: nil)
        }
        self.identification = identification
    }
}
