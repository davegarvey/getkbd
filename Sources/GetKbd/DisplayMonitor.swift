import AppKit
import ColorSync
import CoreGraphics
import Foundation

@MainActor
protocol DisplayHandoffControlling: AnyObject {
    var hasPendingKeyboardRelease: Bool { get }

    func prepareForKeyboardRelease()
    func restoreAfterKeyboardClaim()
}

@MainActor
final class DisplayMonitor: DisplayHandoffControlling {
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
        let mirroredDisplayIdentifier: String
        let mainDisplayIdentifier: String
        let displays: [DisplayState]
    }

    var configuredDisplayIdentifier: String? {
        didSet {
            scheduleEvaluation()
        }
    }

    var debounceInterval: TimeInterval
    var onChange: ((Bool) -> Void)?
    var onConfigurationChange: (() -> Void)?

    private(set) var isPresent = false
    private var screenObserver: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?
    private var displayCallbackRegistered = false
    private var savedExtendedConfiguration: SavedDisplayConfiguration?

    var hasPendingKeyboardRelease: Bool {
        savedExtendedConfiguration != nil
    }

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

    func prepareForKeyboardRelease() {
        if let savedExtendedConfiguration {
            reapplyMirror(for: savedExtendedConfiguration)
            return
        }

        let displayIDs = Self.currentDisplayIDs()
        guard let externalDisplayID = configuredDisplayID(in: displayIDs),
              CGDisplayIsActive(externalDisplayID) != 0,
              displayIDs.allSatisfy({ CGDisplayIsInMirrorSet($0) == 0 }),
              let builtInDisplayID = displayIDs.first(where: {
                  $0 != externalDisplayID &&
                      CGDisplayIsBuiltin($0) != 0 &&
                      CGDisplayIsActive($0) != 0
              }) else {
            return
        }

        let displayStates = displayIDs
            .filter { CGDisplayIsActive($0) != 0 }
            .map(DisplayState.init)
        // Keep the desk display as the mirror master so it remains the primary display.
        guard configureMirror(
            mirroredDisplayID: builtInDisplayID,
            mainDisplayID: externalDisplayID
        ) else {
            return
        }

        let savedConfiguration = SavedDisplayConfiguration(
            mirroredDisplayIdentifier: Self.identifier(for: builtInDisplayID),
            mainDisplayIdentifier: Self.identifier(for: externalDisplayID),
            displays: displayStates
        )
        if !hasExpectedMirror(
            mirroredDisplayIdentifier: Self.identifier(for: builtInDisplayID),
            mainDisplayIdentifier: Self.identifier(for: externalDisplayID)
        ) {
            GetKbdLog.error("display.mirror.failed", "Mirror configuration was not applied completely")
            rollbackMirror(
                mirroredDisplayIdentifier: Self.identifier(for: builtInDisplayID),
                mainDisplayIdentifier: Self.identifier(for: externalDisplayID)
            )
            return
        }

        savedExtendedConfiguration = savedConfiguration
        GetKbdLog.event(
            "display.mirror.started",
            "display=\(builtInDisplayID), master=\(externalDisplayID)"
        )
    }

    private func reapplyMirror(for savedConfiguration: SavedDisplayConfiguration) {
        let currentDisplays = Self.currentDisplaysByIdentifier()
        guard let mirroredDisplayID = currentDisplays[savedConfiguration.mirroredDisplayIdentifier],
              let mainDisplayID = currentDisplays[savedConfiguration.mainDisplayIdentifier],
              CGDisplayIsActive(mirroredDisplayID) != 0,
              CGDisplayIsActive(mainDisplayID) != 0,
              CGDisplayIsInMirrorSet(mirroredDisplayID) == 0,
              CGDisplayIsInMirrorSet(mainDisplayID) == 0,
              noUnrelatedMirrorSets(
                  in: currentDisplays,
                  mirroredDisplayID: mirroredDisplayID,
                  mainDisplayID: mainDisplayID
              ) else {
            return
        }

        guard configureMirror(
            mirroredDisplayID: mirroredDisplayID,
            mainDisplayID: mainDisplayID
        ) else {
            return
        }

        guard hasExpectedMirror(
            mirroredDisplayIdentifier: savedConfiguration.mirroredDisplayIdentifier,
            mainDisplayIdentifier: savedConfiguration.mainDisplayIdentifier
        ) else {
            GetKbdLog.error("display.mirror.failed", "Mirror reconfiguration was not applied completely")
            return
        }

        GetKbdLog.event("display.mirror.reapplied", "display=\(mirroredDisplayID)")
    }

    private func configureMirror(
        mirroredDisplayID: CGDirectDisplayID,
        mainDisplayID: CGDirectDisplayID
    ) -> Bool {
        let displayIDs = Self.currentDisplayIDs()
        guard displayIDs.contains(mirroredDisplayID),
              displayIDs.contains(mainDisplayID),
              CGDisplayIsActive(mirroredDisplayID) != 0,
              CGDisplayIsActive(mainDisplayID) != 0,
              displayIDs.allSatisfy({ CGDisplayIsInMirrorSet($0) == 0 }) else {
            return false
        }

        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success,
              let configuration else {
            GetKbdLog.error("display.mirror.failed", "Unable to begin display configuration")
            return false
        }

        let configureResult = CGConfigureDisplayMirrorOfDisplay(
            configuration,
            mirroredDisplayID,
            mainDisplayID
        )
        guard configureResult == .success else {
            _ = CGCancelDisplayConfiguration(configuration)
            GetKbdLog.error(
                "display.mirror.failed",
                "Unable to mirror display (CGError \(configureResult.rawValue))"
            )
            return false
        }

        let completeResult = CGCompleteDisplayConfiguration(configuration, .forAppOnly)
        guard completeResult == .success else {
            GetKbdLog.error(
                "display.mirror.failed",
                "Unable to apply mirror configuration (CGError \(completeResult.rawValue))"
            )
            return false
        }

        return true
    }

    private func hasExpectedMirror(
        mirroredDisplayIdentifier: String,
        mainDisplayIdentifier: String
    ) -> Bool {
        let currentDisplays = Self.currentDisplaysByIdentifier()
        guard let mirroredDisplayID = currentDisplays[mirroredDisplayIdentifier],
              let mainDisplayID = currentDisplays[mainDisplayIdentifier] else {
            return false
        }

        return CGDisplayIsInMirrorSet(mirroredDisplayID) != 0 &&
            CGDisplayMirrorsDisplay(mirroredDisplayID) == mainDisplayID
    }

    private func rollbackMirror(
        mirroredDisplayIdentifier: String,
        mainDisplayIdentifier: String
    ) {
        let currentDisplays = Self.currentDisplaysByIdentifier()
        guard let mirroredDisplayID = currentDisplays[mirroredDisplayIdentifier],
              let mainDisplayID = currentDisplays[mainDisplayIdentifier],
              CGDisplayIsInMirrorSet(mirroredDisplayID) != 0,
              CGDisplayMirrorsDisplay(mirroredDisplayID) == mainDisplayID else {
            return
        }

        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success,
              let configuration else {
            return
        }

        let unmirrorResult = CGConfigureDisplayMirrorOfDisplay(
            configuration,
            mirroredDisplayID,
            kCGNullDirectDisplay
        )
        guard unmirrorResult == .success else {
            _ = CGCancelDisplayConfiguration(configuration)
            return
        }

        let completeResult = CGCompleteDisplayConfiguration(configuration, .forAppOnly)
        guard completeResult == .success else {
            GetKbdLog.error(
                "display.mirror.failed",
                "Unable to roll back mirror configuration (CGError \(completeResult.rawValue))"
            )
            return
        }

        GetKbdLog.event("display.mirror.rolled-back")
    }

    func restoreAfterKeyboardClaim() {
        guard let savedConfiguration = savedExtendedConfiguration else {
            makeConfiguredDisplayPrimary()
            return
        }

        let currentDisplays = Self.currentDisplaysByIdentifier()
        guard let mirroredDisplayID = currentDisplays[savedConfiguration.mirroredDisplayIdentifier],
              let mainDisplayID = currentDisplays[savedConfiguration.mainDisplayIdentifier] else {
            if configuredDisplayIdentifier != savedConfiguration.mainDisplayIdentifier {
                savedExtendedConfiguration = nil
                makeConfiguredDisplayPrimary()
            }
            return
        }
        guard CGDisplayIsActive(mirroredDisplayID) != 0,
              CGDisplayIsActive(mainDisplayID) != 0,
              noUnrelatedMirrorSets(
                  in: currentDisplays,
                  mirroredDisplayID: mirroredDisplayID,
                  mainDisplayID: mainDisplayID
              ) else {
            return
        }

        let isExpectedMirror = CGDisplayIsInMirrorSet(mirroredDisplayID) != 0 &&
            CGDisplayMirrorsDisplay(mirroredDisplayID) == mainDisplayID
        let isAlreadyExtended = CGDisplayIsInMirrorSet(mirroredDisplayID) == 0 &&
            CGDisplayIsInMirrorSet(mainDisplayID) == 0
        guard isExpectedMirror || isAlreadyExtended else { return }

        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success,
              let configuration else {
            GetKbdLog.error("display.extend.failed", "Unable to begin display configuration")
            return
        }

        if isExpectedMirror {
            let unmirrorResult = CGConfigureDisplayMirrorOfDisplay(
                configuration,
                mirroredDisplayID,
                kCGNullDirectDisplay
            )
            guard unmirrorResult == .success else {
                _ = CGCancelDisplayConfiguration(configuration)
                GetKbdLog.error(
                    "display.extend.failed",
                    "Unable to disable display mirroring (CGError \(unmirrorResult.rawValue))"
                )
                return
            }
        }

        for display in savedConfiguration.displays {
            guard let displayID = currentDisplays[display.identifier] else { continue }
            guard CGDisplayIsActive(displayID) != 0 else { continue }
            if let mode = display.mode?.matchingMode(for: displayID) {
                let modeResult = CGConfigureDisplayWithDisplayMode(
                    configuration,
                    displayID,
                    mode,
                    nil
                )
                guard modeResult == .success else {
                    _ = CGCancelDisplayConfiguration(configuration)
                    GetKbdLog.error(
                        "display.extend.failed",
                        "Unable to restore display mode (CGError \(modeResult.rawValue))"
                    )
                    return
                }
            }
        }

        let originResult = configureOrigins(
            savedConfiguration.displays,
            mainDisplayIdentifier: savedConfiguration.mainDisplayIdentifier,
            currentDisplays: currentDisplays,
            configuration: configuration
        )
        guard originResult == .success else {
            _ = CGCancelDisplayConfiguration(configuration)
            GetKbdLog.error(
                "display.extend.failed",
                "Unable to restore display layout (CGError \(originResult.rawValue))"
            )
            return
        }

        let completeResult = CGCompleteDisplayConfiguration(configuration, .forAppOnly)
        guard completeResult == .success else {
            GetKbdLog.error(
                "display.extend.failed",
                "Unable to apply extended configuration (CGError \(completeResult.rawValue))"
            )
            return
        }

        let restoredDisplays = Self.currentDisplaysByIdentifier()
        guard let restoredMirroredDisplayID = restoredDisplays[savedConfiguration.mirroredDisplayIdentifier],
              let restoredMainDisplayID = restoredDisplays[savedConfiguration.mainDisplayIdentifier],
              CGDisplayIsInMirrorSet(restoredMirroredDisplayID) == 0 else {
            GetKbdLog.error("display.extend.failed", "Display layout was not restored completely")
            return
        }

        if CGMainDisplayID() != restoredMainDisplayID {
            GetKbdLog.error("display.extend.failed", "The selected monitor did not become primary")
            makeDisplayPrimary(displayID: restoredMainDisplayID)
            guard CGMainDisplayID() == restoredMainDisplayID else { return }
        }

        savedExtendedConfiguration = nil
        GetKbdLog.event("display.mirror.ended", "display=\(mirroredDisplayID)")
        makeConfiguredDisplayPrimary()
    }

    private func makeConfiguredDisplayPrimary() {
        let onlineDisplayIDs = Self.currentDisplayIDs()
        guard let displayID = configuredDisplayID(in: onlineDisplayIDs) else { return }
        makeDisplayPrimary(displayID: displayID, onlineDisplayIDs: onlineDisplayIDs)
    }

    private func makeDisplayPrimary(
        displayID: CGDirectDisplayID,
        onlineDisplayIDs: [CGDirectDisplayID]? = nil
    ) {
        let onlineDisplayIDs = onlineDisplayIDs ?? Self.currentDisplayIDs()
        guard onlineDisplayIDs.contains(displayID),
              CGDisplayIsActive(displayID) != 0,
              onlineDisplayIDs.allSatisfy({ CGDisplayIsInMirrorSet($0) == 0 }),
              CGDisplayIsMain(displayID) == 0 else {
            return
        }

        let activeDisplayIDs = onlineDisplayIDs.filter { CGDisplayIsActive($0) != 0 }
        let displayStates = activeDisplayIDs.map(DisplayState.init)
        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success,
              let configuration else {
            GetKbdLog.error("display.primary.failed", "Unable to begin display configuration")
            return
        }

        let originResult = configureOrigins(
            displayStates,
            mainDisplayIdentifier: Self.identifier(for: displayID),
            currentDisplays: Dictionary(
                activeDisplayIDs.map { (Self.identifier(for: $0), $0) },
                uniquingKeysWith: { first, _ in first }
            ),
            configuration: configuration
        )
        guard originResult == .success else {
            _ = CGCancelDisplayConfiguration(configuration)
            GetKbdLog.error(
                "display.primary.failed",
                "Unable to set primary display (CGError \(originResult.rawValue))"
            )
            return
        }

        let completeResult = CGCompleteDisplayConfiguration(configuration, .forAppOnly)
        guard completeResult == .success else {
            GetKbdLog.error(
                "display.primary.failed",
                "Unable to apply primary display (CGError \(completeResult.rawValue))"
            )
            return
        }

        guard CGMainDisplayID() == displayID else {
            GetKbdLog.error("display.primary.failed", "The selected monitor did not become primary")
            return
        }

        GetKbdLog.event("display.primary.set", "display=\(displayID)")
    }

    private func configureOrigins(
        _ displays: [DisplayState],
        mainDisplayIdentifier: String,
        currentDisplays: [String: CGDirectDisplayID],
        configuration: CGDisplayConfigRef
    ) -> CGError {
        let mainDisplay = displays.first { $0.identifier == mainDisplayIdentifier }
        // Display coordinates use the origin to identify the primary display. Translate the
        // saved layout as a whole so relative positions stay unchanged.
        let offsetX = mainDisplay.map { -Int64($0.originX) } ?? 0
        let offsetY = mainDisplay.map { -Int64($0.originY) } ?? 0

        for display in displays {
            guard let displayID = currentDisplays[display.identifier] else { continue }
            guard CGDisplayIsActive(displayID) != 0 else { continue }
            let originResult = CGConfigureDisplayOrigin(
                configuration,
                displayID,
                Int32(Int64(display.originX) + offsetX),
                Int32(Int64(display.originY) + offsetY)
            )
            guard originResult == .success else { return originResult }
        }

        return .success
    }

    private func noUnrelatedMirrorSets(
        in currentDisplays: [String: CGDirectDisplayID],
        mirroredDisplayID: CGDirectDisplayID,
        mainDisplayID: CGDirectDisplayID
    ) -> Bool {
        currentDisplays.values.allSatisfy { displayID in
            displayID == mirroredDisplayID ||
                displayID == mainDisplayID ||
                CGDisplayIsInMirrorSet(displayID) == 0
        }
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

        guard newValue != isPresent else {
            if notify {
                onConfigurationChange?()
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
        onConfigurationChange?()
    }

    private func configuredDisplayID(in displayIDs: [CGDirectDisplayID]) -> CGDirectDisplayID? {
        guard let configuredDisplayIdentifier else { return nil }
        return displayIDs.first {
            Self.identifier(for: $0) == configuredDisplayIdentifier
        }
    }

    private static func currentDisplayIDs() -> [CGDirectDisplayID] {
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
            currentDisplayIDs().map { (identifier(for: $0), $0) },
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
