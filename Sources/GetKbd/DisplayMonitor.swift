import AppKit
import CoreGraphics
import Foundation

@MainActor
protocol DisplayParkingControlling: AnyObject {
    var isPresent: Bool { get }
    var parkingState: DisplayParkingState { get }
    var parkingError: String? { get }
    var onStateChange: (() -> Void)? { get set }

    func park()
    func restore()
}

@MainActor
final class DisplayMonitor: DisplayParkingControlling {
    private struct DisplayModeState {
        let ioDisplayModeID: Int32
        let width: Int
        let height: Int
        let pixelWidth: Int
        let pixelHeight: Int
        let refreshRate: Double
        let ioFlags: UInt32

        init(_ mode: CGDisplayMode) {
            ioDisplayModeID = mode.ioDisplayModeID
            width = mode.width
            height = mode.height
            pixelWidth = mode.pixelWidth
            pixelHeight = mode.pixelHeight
            refreshRate = mode.refreshRate
            ioFlags = mode.ioFlags
        }

        func matchingMode(for displayID: CGDirectDisplayID) -> CGDisplayMode? {
            let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] ?? []
            return modes.first { $0.ioDisplayModeID == ioDisplayModeID } ?? modes.first {
                $0.width == width &&
                    $0.height == height &&
                    $0.pixelWidth == pixelWidth &&
                    $0.pixelHeight == pixelHeight &&
                    abs($0.refreshRate - refreshRate) < 0.01 &&
                    $0.ioFlags == ioFlags
            } ?? modes.first {
                $0.pixelWidth == pixelWidth &&
                    $0.pixelHeight == pixelHeight &&
                    abs($0.refreshRate - refreshRate) < 0.01 &&
                    $0.ioFlags == ioFlags
            } ?? CGDisplayCopyDisplayMode(displayID)
        }
    }

    private struct DisplayState {
        let identifier: String
        let originX: Int32
        let originY: Int32
        let mode: DisplayModeState?

        init(displayID: CGDirectDisplayID) {
            let origin = CGDisplayBounds(displayID).origin
            identifier = DisplayMonitor.identifier(for: displayID)
            originX = Int32(origin.x.rounded())
            originY = Int32(origin.y.rounded())
            mode = CGDisplayCopyDisplayMode(displayID).map(DisplayModeState.init)
        }
    }

    private struct SavedDisplayConfiguration {
        let displays: [DisplayState]
    }

    var configuredDisplayIdentifier: String? {
        didSet {
            scheduleEvaluation()
        }
    }

    var debounceInterval: TimeInterval
    var onChange: ((Bool) -> Void)?
    var onStateChange: (() -> Void)?

    private(set) var isPresent = false
    private(set) var parkingState: DisplayParkingState = .idle
    private(set) var parkingError: String?

    private var screenObserver: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?
    private var displayCallbackRegistered = false
    private var savedConfiguration: SavedDisplayConfiguration?
    private var parkingWindow: NSWindow?

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
        hideParkingWindow()
    }

    func park() {
        guard let displayID = onlineConfiguredDisplayID(),
              CGDisplayIsBuiltin(displayID) == 0 else {
            savedConfiguration = nil
            updateParkingState(.idle)
            return
        }

        guard CGDisplayIsActive(displayID) != 0 else {
            updateParkingState(
                .attentionRequired,
                error: "The selected external display is disabled. Re-enable it in Display Settings before continuing."
            )
            return
        }

        if parkingState == .parked, parkingWindow != nil {
            return
        }

        updateParkingState(.parking)

        if savedConfiguration == nil {
            savedConfiguration = SavedDisplayConfiguration(
                displays: Self.currentOnlineDisplayIDs()
                    .filter { CGDisplayIsActive($0) != 0 }
                    .map(DisplayState.init)
            )
        }

        guard removeMirroringIfNeeded(for: displayID) else {
            updateParkingState(
                .attentionRequired,
                error: "Unable to remove display mirroring before parking the external display."
            )
            return
        }

        guard showParkingWindow(for: displayID) else {
            updateParkingState(
                .attentionRequired,
                error: "Unable to cover the external display while parking it."
            )
            return
        }

        updateParkingState(.parked)
        GetKbdLog.event("display.parked", "display=\(displayID), signal=retained")
    }

    func restore() {
        guard let displayID = configuredDisplayID() else {
            savedConfiguration = nil
            updateParkingState(.idle)
            return
        }

        if parkingState == .restored,
           CGDisplayIsActive(displayID) != 0,
           CGMainDisplayID() == displayID {
            return
        }

        updateParkingState(.restoring)
        hideParkingWindow()

        guard removeMirroringIfNeeded(for: displayID) else {
            updateParkingState(
                .attentionRequired,
                error: "Unable to remove display mirroring before restoring the external display."
            )
            return
        }

        let restored = if let savedConfiguration {
            restoreConfiguration(savedConfiguration)
        } else {
            makeConfiguredDisplayPrimary()
        }

        guard restored,
              CGDisplayIsActive(displayID) != 0,
              CGMainDisplayID() == displayID else {
            updateParkingState(
                .attentionRequired,
                error: "The external display could not be restored as the primary display."
            )
            return
        }

        savedConfiguration = nil
        updateParkingState(.restored)
        GetKbdLog.event("display.restored", "display=\(displayID)")
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
        let names = Dictionary(
            NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, String)? in
                guard let displayID = displayID(for: screen) else { return nil }
                return (displayID, screen.localizedName)
            },
            uniquingKeysWith: { first, _ in first }
        )

        return currentOnlineDisplayIDs().compactMap { displayID in
            guard CGDisplayIsBuiltin(displayID) == 0 else { return nil }
            return DisplayDescriptor(
                identifier: identifier(for: displayID),
                name: names[displayID] ?? "External display",
                isBuiltIn: false
            )
        }
    }

    private func evaluate(notify: Bool) {
        let newValue = configuredDisplayID() != nil

        guard newValue != isPresent else {
            if notify {
                onStateChange?()
            }
            return
        }

        isPresent = newValue

        guard notify else { return }
        let configured = configuredDisplayIdentifier ?? "none"
        GetKbdLog.event(
            newValue ? "monitor.connected" : "monitor.disconnected",
            "configured=\(configured)"
        )
        onChange?(newValue)
        onStateChange?()
    }

    private func configuredDisplayID() -> CGDirectDisplayID? {
        onlineConfiguredDisplayID()
    }

    private func onlineConfiguredDisplayID() -> CGDirectDisplayID? {
        configuredDisplayID(in: Self.currentOnlineDisplayIDs())
    }

    private func configuredDisplayID(in displayIDs: [CGDirectDisplayID]) -> CGDirectDisplayID? {
        guard let configuredDisplayIdentifier else { return nil }
        return displayIDs.first {
            Self.identifier(for: $0) == configuredDisplayIdentifier
        }
    }

    private func removeMirroringIfNeeded(for displayID: CGDirectDisplayID) -> Bool {
        let onlineDisplayIDs = Self.currentOnlineDisplayIDs()
        let mirrors: [CGDirectDisplayID]
        if CGDisplayMirrorsDisplay(displayID) != kCGNullDirectDisplay {
            mirrors = [displayID]
        } else if CGDisplayIsInMirrorSet(displayID) != 0 {
            mirrors = onlineDisplayIDs.filter {
                $0 != displayID && CGDisplayMirrorsDisplay($0) == displayID
            }
        } else {
            mirrors = []
        }
        guard !mirrors.isEmpty else { return true }

        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success,
              let configuration else {
            return false
        }

        for displayID in mirrors {
            let result = CGConfigureDisplayMirrorOfDisplay(
                configuration,
                displayID,
                kCGNullDirectDisplay
            )
            guard result == .success else {
                _ = CGCancelDisplayConfiguration(configuration)
                return false
            }
        }

        let result = CGCompleteDisplayConfiguration(configuration, .forAppOnly)
        guard result == .success else {
            GetKbdLog.error(
                "display.unmirror.failed",
                "Unable to remove display mirroring (CGError \(result.rawValue))"
            )
            return false
        }

        return true
    }

    private func restoreConfiguration(_ savedConfiguration: SavedDisplayConfiguration) -> Bool {
        guard let configuredDisplayIdentifier,
              let configuredDisplayID = configuredDisplayID() else {
            return false
        }

        let currentDisplays = Self.currentDisplaysByIdentifier()
        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success,
              let configuration else {
            return false
        }

        for display in savedConfiguration.displays {
            guard let displayID = currentDisplays[display.identifier],
                  CGDisplayIsActive(displayID) != 0 else {
                continue
            }
            guard let mode = display.mode?.matchingMode(for: displayID) else { continue }

            let result = CGConfigureDisplayWithDisplayMode(
                configuration,
                displayID,
                mode,
                nil
            )
            guard result == .success else {
                _ = CGCancelDisplayConfiguration(configuration)
                return false
            }
        }

        let originResult = configureOrigins(
            savedConfiguration.displays,
            mainDisplayIdentifier: configuredDisplayIdentifier,
            currentDisplays: currentDisplays,
            configuration: configuration
        )
        guard originResult == .success else {
            _ = CGCancelDisplayConfiguration(configuration)
            return false
        }

        let completeResult = CGCompleteDisplayConfiguration(configuration, .forAppOnly)
        guard completeResult == .success else { return false }

        let finalDisplays = Self.currentDisplaysByIdentifier()
        guard let finalConfiguredID = finalDisplays[configuredDisplayIdentifier],
              finalConfiguredID == configuredDisplayID,
              CGDisplayIsActive(finalConfiguredID) != 0,
              CGMainDisplayID() == finalConfiguredID else {
            return false
        }

        return true
    }

    private func makeConfiguredDisplayPrimary() -> Bool {
        guard let configuredDisplayID = configuredDisplayID(),
              CGDisplayIsActive(configuredDisplayID) != 0 else {
            return false
        }

        let activeDisplayIDs = Self.currentOnlineDisplayIDs()
            .filter { CGDisplayIsActive($0) != 0 }
        let displayStates = activeDisplayIDs.map(DisplayState.init)
        let currentDisplays = Dictionary(
            activeDisplayIDs.map { (Self.identifier(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success,
              let configuration else {
            return false
        }

        let originResult = configureOrigins(
            displayStates,
            mainDisplayIdentifier: Self.identifier(for: configuredDisplayID),
            currentDisplays: currentDisplays,
            configuration: configuration
        )
        guard originResult == .success else {
            _ = CGCancelDisplayConfiguration(configuration)
            return false
        }

        let completeResult = CGCompleteDisplayConfiguration(configuration, .forAppOnly)
        guard completeResult == .success else { return false }
        return CGMainDisplayID() == configuredDisplayID
    }

    private func configureOrigins(
        _ displays: [DisplayState],
        mainDisplayIdentifier: String,
        currentDisplays: [String: CGDirectDisplayID],
        configuration: CGDisplayConfigRef
    ) -> CGError {
        let mainDisplay = displays.first { $0.identifier == mainDisplayIdentifier }
        let offsetX = mainDisplay.map { -Int64($0.originX) } ?? 0
        let offsetY = mainDisplay.map { -Int64($0.originY) } ?? 0

        for display in displays {
            guard let displayID = currentDisplays[display.identifier],
                  CGDisplayIsActive(displayID) != 0 else {
                continue
            }

            let originResult = CGConfigureDisplayOrigin(
                configuration,
                displayID,
                Int32(Int64(display.originX) + offsetX),
                Int32(Int64(display.originY) + offsetY)
            )
            guard originResult == .success else { return originResult }
        }

        if mainDisplay == nil,
           let configuredDisplayIdentifier,
           let displayID = currentDisplays[configuredDisplayIdentifier] {
            return CGConfigureDisplayOrigin(configuration, displayID, 0, 0)
        }

        return .success
    }

    private func updateParkingState(_ state: DisplayParkingState, error: String? = nil) {
        guard parkingState != state || parkingError != error else { return }
        parkingState = state
        parkingError = error
        onStateChange?()
    }

    private func showParkingWindow(for displayID: CGDirectDisplayID) -> Bool {
        let frame = NSScreen.screens.first { $0.cgDirectDisplayID == displayID }?.frame
            ?? CGDisplayBounds(displayID)

        guard !frame.isEmpty else { return false }

        if let parkingWindow {
            parkingWindow.setFrame(frame, display: true)
            parkingWindow.orderFrontRegardless()
            return true
        }

        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = true

        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = view
        window.orderFrontRegardless()
        parkingWindow = window
        return true
    }

    private func hideParkingWindow() {
        parkingWindow?.orderOut(nil)
        parkingWindow = nil
    }

    private static func currentOnlineDisplayIDs() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success,
              displayCount > 0 else {
            return []
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        let result = displayIDs.withUnsafeMutableBufferPointer { buffer in
            CGGetOnlineDisplayList(displayCount, buffer.baseAddress, &displayCount)
        }
        guard result == .success else { return [] }
        return Array(displayIDs.prefix(Int(displayCount)))
    }

    private static func currentDisplaysByIdentifier() -> [String: CGDirectDisplayID] {
        Dictionary(
            currentOnlineDisplayIDs().map { (identifier(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
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

    nonisolated private static func identifier(for displayID: CGDirectDisplayID) -> String {
        if let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(displayID) {
            let uuid = unmanagedUUID.takeRetainedValue()
            return CFUUIDCreateString(nil, uuid) as String
        }

        return "display-\(CGDisplayVendorNumber(displayID))-\(CGDisplayModelNumber(displayID))-\(CGDisplaySerialNumber(displayID))"
    }
}
