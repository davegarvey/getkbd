import AppKit
import ColorSync
import CoreGraphics
import Foundation

@MainActor
final class DisplayMonitor {
    var configuredDisplayIdentifier: String? {
        didSet {
            scheduleEvaluation()
        }
    }

    var debounceInterval: TimeInterval
    var onChange: ((Bool) -> Void)?

    private(set) var isPresent = false
    private var screenObserver: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?
    private var displayCallbackRegistered = false

    init(configuredDisplayIdentifier: String?, debounceInterval: TimeInterval = 1.5) {
        self.configuredDisplayIdentifier = configuredDisplayIdentifier
        self.debounceInterval = debounceInterval
    }

    @discardableResult
    func start() -> Bool {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        displayCallbackRegistered = CGDisplayRegisterReconfigurationCallback(
            Self.displayReconfigurationCallback,
            context
        ) == .success

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleEvaluation()
            }
        }

        evaluate(notify: false)
        return isPresent
    }

    func stop() {
        if displayCallbackRegistered {
            let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            _ = CGDisplayRemoveReconfigurationCallback(Self.displayReconfigurationCallback, context)
            displayCallbackRegistered = false
        }

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        debounceTask?.cancel()
        debounceTask = nil
    }

    func scheduleEvaluation() {
        debounceTask?.cancel()
        let delay = UInt64(max(0, debounceInterval) * 1_000_000_000)

        debounceTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }

            guard !Task.isCancelled else { return }
            self?.evaluate(notify: true)
        }
    }

    static func currentDisplays() -> [DisplayDescriptor] {
        NSScreen.screens.compactMap { (screen: NSScreen) -> DisplayDescriptor? in
            guard let displayID = displayID(for: screen) else { return nil }

            return DisplayDescriptor(
                identifier: identifier(for: displayID),
                name: screen.localizedName,
                isBuiltIn: CGDisplayIsBuiltin(displayID) != 0
            )
        }
    }

    private func evaluate(notify: Bool) {
        let newValue = configuredDisplayIdentifier.map { identifier in
            Self.currentDisplays().contains { $0.identifier == identifier }
        } ?? false

        guard newValue != isPresent else { return }
        isPresent = newValue

        guard notify else { return }
        let configured = configuredDisplayIdentifier ?? "none"
        GetKbdLog.event(
            newValue ? "monitor.connected" : "monitor.disconnected",
            "configured=\(configured)"
        )
        onChange?(newValue)
    }

    private static let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = {
        _, _, userInfo in
        guard let userInfo else { return }

        let contextAddress = UInt(bitPattern: userInfo)
        Task { @MainActor in
            guard let context = UnsafeMutableRawPointer(bitPattern: contextAddress) else { return }
            let monitor = Unmanaged<DisplayMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.scheduleEvaluation()
        }
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.cgDirectDisplayID
    }

    private static func identifier(for displayID: CGDirectDisplayID) -> String {
        if let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(displayID) {
            let uuid = unmanagedUUID.takeRetainedValue()
            return CFUUIDCreateString(nil, uuid) as String
        }

        return "display-\(CGDisplayVendorNumber(displayID))-\(CGDisplayModelNumber(displayID))-\(CGDisplaySerialNumber(displayID))"
    }
}
