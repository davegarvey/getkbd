import Foundation

/// Learns which monitor input belongs to each Mac by reading the input after the hub
/// group settles. A reading is accepted only when two consecutive readings agree,
/// because the monitor stops answering or drops readings while it changes input.
@MainActor
final class MonitorInputLearner {
    private let control: MonitorInputControl
    private let readingInterval: TimeInterval
    private let maximumReadings: Int
    private var task: Task<Void, Never>?

    /// Called with an accepted reading and whether it belongs to this Mac.
    var onReading: ((_ value: Int, _ isThisMac: Bool, _ displayIdentifier: String) -> Void)?
    /// Called after each attempt with whether the monitor answered at all.
    var onAvailabilityChange: ((Bool) -> Void)?

    init(control: MonitorInputControl, readingInterval: TimeInterval = 1, maximumReadings: Int = 8) {
        self.control = control
        self.readingInterval = readingInterval
        self.maximumReadings = maximumReadings
    }

    /// Starts learning for the current hub state, cancelling any earlier attempt.
    func learn(displayIdentifier: String, hubPresent: Bool) {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            let value = await self.agreedReading(displayIdentifier: displayIdentifier)
            guard !Task.isCancelled else { return }
            self.task = nil
            if let value {
                self.onReading?(value, hubPresent, displayIdentifier)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func waitForIdle() async {
        await task?.value
    }

    private func agreedReading(displayIdentifier: String) async -> Int? {
        var previous: Int?
        var answered = false

        for attempt in 0..<maximumReadings {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: UInt64(readingInterval * 1_000_000_000))
            }
            guard !Task.isCancelled else { return nil }

            let reading = await control.readInput(displayIdentifier: displayIdentifier)
            guard !Task.isCancelled else { return nil }
            if reading != nil, !answered {
                answered = true
                onAvailabilityChange?(true)
            }
            if let reading, reading == previous {
                return reading
            }
            previous = reading
        }

        if !answered {
            onAvailabilityChange?(false)
        }
        return nil
    }
}
