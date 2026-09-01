import AppKit
import ColorSync
import CoreGraphics
import Foundation

@MainActor
protocol DisplayHandoffControlling: AnyObject {
    var hasPendingKeyboardRelease: Bool { get }
    var handoffState: DisplayHandoffState { get }
    var handoffError: String? { get }
    var onHandoffStateChange: (() -> Void)? { get set }

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
        let mirrorMasterIdentifier: String
        let restoredMainDisplayIdentifier: String
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
    var onHandoffStateChange: (() -> Void)?

    private(set) var isPresent = false
    private var screenObserver: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?
    private var displayCallbackRegistered = false
    private var savedExtendedConfiguration: SavedDisplayConfiguration?
    private(set) var handoffState: DisplayHandoffState = .idle
    private(set) var handoffError: String?

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
        updateHandoffState(.preparing)

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
            updateHandoffState(.idle)
            return
        }

        let displayStates = displayIDs
            .filter { CGDisplayIsActive($0) != 0 }
            .map(DisplayState.init)

        // Keep the laptop as the mirror master so its native scaling and desktop remain local.
        guard makeDisplayPrimary(displayID: builtInDisplayID, onlineDisplayIDs: displayIDs) else {
            updateHandoffState(
                .attentionRequired,
                error: "Unable to make the laptop the primary display."
            )
            return
        }

        guard configureMirror(
            mirroredDisplayID: externalDisplayID,
            mirrorMasterID: builtInDisplayID
        ) else {
            updateHandoffState(
                .attentionRequired,
                error: "Unable to protect the shared display layout."
            )
            return
        }

        let savedConfiguration = SavedDisplayConfiguration(
            mirroredDisplayIdentifier: Self.identifier(for: externalDisplayID),
            mirrorMasterIdentifier: Self.identifier(for: builtInDisplayID),
            restoredMainDisplayIdentifier: Self.identifier(for: externalDisplayID),
            displays: displayStates
        )
        if !hasExpectedMirror(
            mirroredDisplayIdentifier: Self.identifier(for: externalDisplayID),
            mirrorMasterIdentifier: Self.identifier(for: builtInDisplayID)
        ) {
            GetKbdLog.error("display.mirror.failed", "Mirror configuration was not applied completely")
            rollbackMirror(
                mirroredDisplayIdentifier: Self.identifier(for: externalDisplayID),
                mirrorMasterIdentifier: Self.identifier(for: builtInDisplayID)
            )
            updateHandoffState(
                .attentionRequired,
                error: "The shared display could not be protected."
            )
            return
        }

        savedExtendedConfiguration = savedConfiguration
        updateHandoffState(.protected)
        GetKbdLog.event(
            "display.mirror.started",
            "display=\(externalDisplayID), master=\(builtInDisplayID)"
        )
    }

    private func reapplyMirror(for savedConfiguration: SavedDisplayConfiguration) {
        updateHandoffState(.preparing)

        let currentDisplays = Self.currentDisplaysByIdentifier()
        guard let mirroredDisplayID = currentDisplays[savedConfiguration.mirroredDisplayIdentifier],
              let mirrorMasterID = currentDisplays[savedConfiguration.mirrorMasterIdentifier],
              CGDisplayIsActive(mirroredDisplayID) != 0,
              CGDisplayIsActive(mirrorMasterID) != 0,
              noUnrelatedMirrorSets(
                  in: currentDisplays,
                  mirroredDisplayID: mirroredDisplayID,
                  mainDisplayID: mirrorMasterID
              ) else {
            updateHandoffState(
                .attentionRequired,
                error: "The shared display changed before it could be protected."
            )
            return
        }

        let isExpectedMirror = CGDisplayIsInMirrorSet(mirroredDisplayID) != 0 &&
            CGDisplayMirrorsDisplay(mirroredDisplayID) == mirrorMasterID
        if isExpectedMirror {
            guard CGMainDisplayID() == mirrorMasterID else {
                updateHandoffState(
                    .attentionRequired,
                    error: "The shared display changed before it could be protected."
                )
                return
            }
            updateHandoffState(.protected)
            return
        }

        guard CGDisplayIsInMirrorSet(mirroredDisplayID) == 0,
              CGDisplayIsInMirrorSet(mirrorMasterID) == 0 else {
            updateHandoffState(
                .attentionRequired,
                error: "The shared display changed before it could be protected."
            )
            return
        }

        guard makeDisplayPrimary(displayID: mirrorMasterID) else {
            updateHandoffState(
                .attentionRequired,
                error: "Unable to make the laptop the primary display."
            )
            return
        }

        guard configureMirror(
            mirroredDisplayID: mirroredDisplayID,
            mirrorMasterID: mirrorMasterID
        ) else {
            updateHandoffState(
                .attentionRequired,
                error: "Unable to protect the shared display layout."
            )
            return
        }

        guard hasExpectedMirror(
            mirroredDisplayIdentifier: savedConfiguration.mirroredDisplayIdentifier,
            mirrorMasterIdentifier: savedConfiguration.mirrorMasterIdentifier
        ) else {
            GetKbdLog.error("display.mirror.failed", "Mirror reconfiguration was not applied completely")
            updateHandoffState(
                .attentionRequired,
                error: "The shared display could not be protected."
            )
            return
        }

        updateHandoffState(.protected)
        GetKbdLog.event("display.mirror.reapplied", "display=\(mirroredDisplayID)")
    }

    private func configureMirror(
        mirroredDisplayID: CGDirectDisplayID,
        mirrorMasterID: CGDirectDisplayID
    ) -> Bool {
        let displayIDs = Self.currentDisplayIDs()
        guard displayIDs.contains(mirroredDisplayID),
              displayIDs.contains(mirrorMasterID),
              CGDisplayIsActive(mirroredDisplayID) != 0,
              CGDisplayIsActive(mirrorMasterID) != 0,
              CGMainDisplayID() == mirrorMasterID,
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
            mirrorMasterID
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
        mirrorMasterIdentifier: String
    ) -> Bool {
        let currentDisplays = Self.currentDisplaysByIdentifier()
        guard let mirroredDisplayID = currentDisplays[mirroredDisplayIdentifier],
              let mirrorMasterID = currentDisplays[mirrorMasterIdentifier] else {
            return false
        }

        return CGDisplayIsInMirrorSet(mirroredDisplayID) != 0 &&
            CGDisplayMirrorsDisplay(mirroredDisplayID) == mirrorMasterID
    }

    private func rollbackMirror(
        mirroredDisplayIdentifier: String,
        mirrorMasterIdentifier: String
    ) {
        let currentDisplays = Self.currentDisplaysByIdentifier()
        guard let mirroredDisplayID = currentDisplays[mirroredDisplayIdentifier],
              let mirrorMasterID = currentDisplays[mirrorMasterIdentifier],
              CGDisplayIsInMirrorSet(mirroredDisplayID) != 0,
              CGDisplayMirrorsDisplay(mirroredDisplayID) == mirrorMasterID else {
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

        updateHandoffState(.restoring)

        let currentDisplays = Self.currentDisplaysByIdentifier()
        guard let mirroredDisplayID = currentDisplays[savedConfiguration.mirroredDisplayIdentifier],
              let mirrorMasterID = currentDisplays[savedConfiguration.mirrorMasterIdentifier],
              let restoredMainID = currentDisplays[savedConfiguration.restoredMainDisplayIdentifier] else {
            if configuredDisplayIdentifier != savedConfiguration.restoredMainDisplayIdentifier {
                savedExtendedConfiguration = nil
                makeConfiguredDisplayPrimary()
                updateHandoffState(.idle)
            } else {
                updateHandoffState(
                    .attentionRequired,
                    error: "The shared display is not available to restore."
                )
            }
            return
        }
        guard CGDisplayIsActive(mirroredDisplayID) != 0,
              CGDisplayIsActive(mirrorMasterID) != 0,
              CGDisplayIsActive(restoredMainID) != 0,
              noUnrelatedMirrorSets(
                  in: currentDisplays,
                  mirroredDisplayID: mirroredDisplayID,
                  mainDisplayID: mirrorMasterID
              ) else {
            updateHandoffState(
                .attentionRequired,
                error: "The display arrangement changed before it could be restored."
            )
            return
        }

        let isExpectedMirror = CGDisplayIsInMirrorSet(mirroredDisplayID) != 0 &&
            CGDisplayMirrorsDisplay(mirroredDisplayID) == mirrorMasterID
        let isAlreadyExtended = CGDisplayIsInMirrorSet(mirroredDisplayID) == 0 &&
            CGDisplayIsInMirrorSet(mirrorMasterID) == 0
        guard isExpectedMirror || isAlreadyExtended else {
            updateHandoffState(
                .attentionRequired,
                error: "The display arrangement could not be recognized."
            )
            return
        }

        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success,
              let configuration else {
            GetKbdLog.error("display.extend.failed", "Unable to begin display configuration")
            updateHandoffState(
                .attentionRequired,
                error: "Unable to begin restoring the display layout."
            )
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
                updateHandoffState(
                    .attentionRequired,
                    error: "Unable to stop temporary display mirroring."
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
                    updateHandoffState(
                        .attentionRequired,
                        error: "Unable to restore a display mode."
                    )
                    return
                }
            }
        }

        let originResult = configureOrigins(
            savedConfiguration.displays,
            mainDisplayIdentifier: savedConfiguration.restoredMainDisplayIdentifier,
            currentDisplays: currentDisplays,
            configuration: configuration
        )
        guard originResult == .success else {
            _ = CGCancelDisplayConfiguration(configuration)
            GetKbdLog.error(
                "display.extend.failed",
                "Unable to restore display layout (CGError \(originResult.rawValue))"
            )
            updateHandoffState(
                .attentionRequired,
                error: "Unable to restore the display layout."
            )
            return
        }

        let completeResult = CGCompleteDisplayConfiguration(configuration, .forAppOnly)
        guard completeResult == .success else {
            GetKbdLog.error(
                "display.extend.failed",
                "Unable to apply extended configuration (CGError \(completeResult.rawValue))"
            )
            updateHandoffState(
                .attentionRequired,
                error: "Unable to apply the restored display layout."
            )
            return
        }

        let restoredDisplays = Self.currentDisplaysByIdentifier()
        guard let restoredMirroredDisplayID = restoredDisplays[savedConfiguration.mirroredDisplayIdentifier],
              let restoredMainDisplayID = restoredDisplays[savedConfiguration.restoredMainDisplayIdentifier],
              CGDisplayIsInMirrorSet(restoredMirroredDisplayID) == 0,
              CGDisplayIsInMirrorSet(restoredMainDisplayID) == 0 else {
            GetKbdLog.error("display.extend.failed", "Display layout was not restored completely")
            updateHandoffState(
                .attentionRequired,
                error: "The display layout was not restored completely."
            )
            return
        }

        if CGMainDisplayID() != restoredMainDisplayID {
            GetKbdLog.error("display.extend.failed", "The selected monitor did not become primary")
            guard makeDisplayPrimary(displayID: restoredMainDisplayID),
                  CGMainDisplayID() == restoredMainDisplayID else {
                updateHandoffState(
                    .attentionRequired,
                    error: "The selected monitor could not become primary."
                )
                return
            }
        }

        savedExtendedConfiguration = nil
        updateHandoffState(.restored)
        GetKbdLog.event("display.mirror.ended", "display=\(mirroredDisplayID)")
        makeConfiguredDisplayPrimary()
    }

    private func makeConfiguredDisplayPrimary() {
        let onlineDisplayIDs = Self.currentDisplayIDs()
        guard let displayID = configuredDisplayID(in: onlineDisplayIDs) else { return }
        makeDisplayPrimary(displayID: displayID, onlineDisplayIDs: onlineDisplayIDs)
    }

    @discardableResult
    private func makeDisplayPrimary(
        displayID: CGDirectDisplayID,
        onlineDisplayIDs: [CGDirectDisplayID]? = nil
    ) -> Bool {
        let onlineDisplayIDs = onlineDisplayIDs ?? Self.currentDisplayIDs()
        guard onlineDisplayIDs.contains(displayID),
              CGDisplayIsActive(displayID) != 0,
              onlineDisplayIDs.allSatisfy({ CGDisplayIsInMirrorSet($0) == 0 }) else {
            return false
        }
        guard CGDisplayIsMain(displayID) == 0 else {
            return true
        }

        let activeDisplayIDs = onlineDisplayIDs.filter { CGDisplayIsActive($0) != 0 }
        let displayStates = activeDisplayIDs.map(DisplayState.init)
        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success,
              let configuration else {
            GetKbdLog.error("display.primary.failed", "Unable to begin display configuration")
            return false
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
            return false
        }

        let completeResult = CGCompleteDisplayConfiguration(configuration, .forAppOnly)
        guard completeResult == .success else {
            GetKbdLog.error(
                "display.primary.failed",
                "Unable to apply primary display (CGError \(completeResult.rawValue))"
            )
            return false
        }

        guard CGMainDisplayID() == displayID else {
            GetKbdLog.error("display.primary.failed", "The selected monitor did not become primary")
            return false
        }

        GetKbdLog.event("display.primary.set", "display=\(displayID)")
        return true
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

    private func updateHandoffState(_ state: DisplayHandoffState, error: String? = nil) {
        guard handoffState != state || handoffError != error else { return }
        handoffState = state
        handoffError = error
        onHandoffStateChange?()
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
