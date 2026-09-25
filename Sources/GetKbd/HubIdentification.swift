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

    private let baseline: [String: USBHubDescriptor]
    private let startedAt: Date
    private var current: [String: USBHubDescriptor]
    private var lastChangeAt: Date
    private var hasUnsettledChange = false
    private var changedSinceBaseline = Set<String>()

    init(hubs: [USBHubDescriptor], at date: Date) {
        baseline = Self.keyed(hubs)
        current = baseline
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
        current = keyed
        lastChangeAt = date
        hasUnsettledChange = true
    }

    mutating func tick(at date: Date) {
        guard !isFinished else { return }

        if hasUnsettledChange, date.timeIntervalSince(lastChangeAt) >= Self.settleInterval {
            hasUnsettledChange = false
            evaluateSettledSnapshot()
            if isFinished { return }
        }

        if date.timeIntervalSince(startedAt) >= Self.timeout {
            phase = .timedOut
        }
    }

    private mutating func evaluateSettledSnapshot() {
        let differing = Set(baseline.keys).symmetricDifference(current.keys)
        changedSinceBaseline.formUnion(differing)

        let returned = changedSinceBaseline.subtracting(differing)
        guard returned.isEmpty else {
            let descriptors = returned
                .compactMap { current[$0] ?? baseline[$0] }
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
