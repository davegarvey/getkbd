import XCTest
@testable import GetKbd

final class MonitorInputTests: XCTestCase {
    func testReplyParsing() {
        let captured: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x60, 0x00, 0x00, 0x15, 0x00, 0x13, 0xD2, 0x00]
        XCTAssertEqual(DDCInputReply.currentValue(from: captured), 19)

        var wrongCode = captured
        wrongCode[4] = 0x10
        XCTAssertNil(DDCInputReply.currentValue(from: wrongCode))

        var unsupported = captured
        unsupported[3] = 0x01
        XCTAssertNil(DDCInputReply.currentValue(from: unsupported))

        XCTAssertNil(DDCInputReply.currentValue(from: Array(captured.prefix(6))))
    }

    func testRecordingLearnsBothInputsAndRejectsConflicts() {
        let thisMac = LearnedMonitorInputs.recording(19, forThisMac: true, displayIdentifier: "d", into: nil)
        XCTAssertEqual(thisMac, LearnedMonitorInputs(displayIdentifier: "d", thisMac: 19, otherMac: nil))

        let both = LearnedMonitorInputs.recording(21, forThisMac: false, displayIdentifier: "d", into: thisMac)
        XCTAssertEqual(both, LearnedMonitorInputs(displayIdentifier: "d", thisMac: 19, otherMac: 21))

        XCTAssertNil(LearnedMonitorInputs.recording(19, forThisMac: false, displayIdentifier: "d", into: both))

        let otherDisplay = LearnedMonitorInputs.recording(15, forThisMac: true, displayIdentifier: "e", into: both)
        XCTAssertEqual(otherDisplay, LearnedMonitorInputs(displayIdentifier: "e", thisMac: 15, otherMac: nil))
    }

    func testSettingsWithoutInputsDecodeAndInputsForAnotherDisplayAreIgnored() throws {
        let json = #"{"selectedDisplay": {"identifier": "d", "name": "D", "isBuiltIn": false}}"#
        var settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertNil(settings.monitorInputs)

        settings.monitorInputs = LearnedMonitorInputs(displayIdentifier: "other", thisMac: 19, otherMac: 21)
        XCTAssertNil(settings.currentMonitorInputs)

        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), settings)
    }

    @MainActor
    func testLearnerAcceptsTwoAgreeingReadings() async {
        let control = FakeMonitorInputControl(readings: [nil, 21, 19, 21, 21])
        let learner = MonitorInputLearner(control: control, readingInterval: 0)
        var recorded: (Int, Bool)?
        learner.onReading = { value, isThisMac, _ in recorded = (value, isThisMac) }

        learner.learn(displayIdentifier: "d", hubPresent: false)
        await learner.waitForIdle()

        XCTAssertEqual(recorded?.0, 21)
        XCTAssertEqual(recorded?.1, false)
    }

    @MainActor
    func testLearnerReportsUnavailableWhenMonitorNeverAnswers() async {
        let control = FakeMonitorInputControl(readings: [])
        let learner = MonitorInputLearner(control: control, readingInterval: 0, maximumReadings: 3)
        var available: Bool?
        var recorded = false
        learner.onAvailabilityChange = { available = $0 }
        learner.onReading = { _, _, _ in recorded = true }

        learner.learn(displayIdentifier: "d", hubPresent: true)
        await learner.waitForIdle()

        XCTAssertEqual(available, false)
        XCTAssertFalse(recorded)
    }

    @MainActor
    func testNewerTransitionCancelsEarlierLearning() async {
        let control = FakeMonitorInputControl(readings: [19, 19, 21, 21])
        let learner = MonitorInputLearner(control: control, readingInterval: 0)
        var recorded: [Bool] = []
        learner.onReading = { _, isThisMac, _ in recorded.append(isThisMac) }

        learner.learn(displayIdentifier: "d", hubPresent: true)
        learner.learn(displayIdentifier: "d", hubPresent: false)
        await learner.waitForIdle()

        XCTAssertEqual(recorded, [false])
    }
}

final class FakeMonitorInputControl: MonitorInputControl, @unchecked Sendable {
    private let lock = NSLock()
    private var readings: [Int?]
    private(set) var writes: [Int] = []

    init(readings: [Int?]) {
        self.readings = readings
    }

    func readInput(displayIdentifier: String) async -> Int? {
        lock.withLock { readings.isEmpty ? nil : readings.removeFirst() }
    }

    func setInput(_ value: Int, displayIdentifier: String) async -> Bool {
        lock.withLock { writes.append(value) }
        return true
    }
}
