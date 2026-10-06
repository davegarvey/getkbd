import AppKit
import Foundation

@MainActor
final class SleepMonitor {
    var onWillSleep: (() -> Void)?
    var onDidWake: (() -> Void)?
    var onScreensDidSleep: (() -> Void)?
    var onScreensDidWake: (() -> Void)?

    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.notificationCenter = notificationCenter
    }

    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = notificationCenter

        observers.append(
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    GetKbdLog.event("system.sleep")
                    self?.onWillSleep?()
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    GetKbdLog.event("system.wake")
                    self?.onDidWake?()
                }
            }
        )
        observers.append(
            center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    GetKbdLog.event("screens.sleep")
                    self?.onScreensDidSleep?()
                }
            }
        )
        observers.append(
            center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    GetKbdLog.event("screens.wake")
                    self?.onScreensDidWake?()
                }
            }
        )

    }

    func stop() {
        let center = notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

}
