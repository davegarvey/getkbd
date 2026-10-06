import AppKit
import XCTest
@testable import GetKbd

@MainActor
final class SleepMonitorTests: XCTestCase {
    func testScreenNotificationsAreIndependentAndStopRemovesObservers() async {
        let center = NotificationCenter()
        let monitor = SleepMonitor(notificationCenter: center)
        var screenSleeps = 0
        var screenWakes = 0
        var systemEvents = 0
        monitor.onScreensDidSleep = { screenSleeps += 1 }
        monitor.onScreensDidWake = { screenWakes += 1 }
        monitor.onWillSleep = { systemEvents += 1 }
        monitor.onDidWake = { systemEvents += 1 }
        monitor.start()
        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(screenSleeps, 1)
        XCTAssertEqual(screenWakes, 1)
        XCTAssertEqual(systemEvents, 0)
        monitor.stop()
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(screenWakes, 1)
    }
}
