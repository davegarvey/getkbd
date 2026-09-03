import AppKit
import CoreGraphics
import Foundation

struct DisplayPrimarySnapshot: Equatable, Sendable {
    let identifier: String
    let isBuiltIn: Bool
    let isOnline: Bool
    let isActive: Bool
    let originX: Int32?
    let originY: Int32?
    let isMirrored: Bool
}

struct DisplayOrigin: Equatable, Sendable {
    let identifier: String
    let x: Int32
    let y: Int32
}

enum DisplayPrimaryPlanner {
    static func targetIdentifier(
        configuredDisplayIdentifier: String?,
        hubConfigured: Bool,
        hubPresent: Bool,
        isSleeping: Bool,
        displays: [DisplayPrimarySnapshot]
    ) -> String? {
        guard !isSleeping,
              hubConfigured,
              let configuredDisplayIdentifier,
              let selectedDisplay = displays.first(where: {
                  $0.identifier == configuredDisplayIdentifier && $0.isOnline
              }) else {
            return nil
        }

        if hubPresent {
            return selectedDisplay.isActive ? selectedDisplay.identifier : nil
        }

        return displays.first(where: { $0.isBuiltIn && $0.isActive })?.identifier
    }

    static func translatedOrigins(
        targetIdentifier: String,
        displays: [DisplayPrimarySnapshot]
    ) -> [DisplayOrigin]? {
        let activeDisplays = displays.filter(\.isActive)
        guard activeDisplays.allSatisfy({ $0.originX != nil && $0.originY != nil }) else {
            return nil
        }

        let currentOrigins = activeDisplays.map { display in
            DisplayOrigin(
                identifier: display.identifier,
                x: display.originX!,
                y: display.originY!
            )
        }
        guard let target = currentOrigins.first(where: { $0.identifier == targetIdentifier }) else {
            return nil
        }

        let offsetX = -Int64(target.x)
        let offsetY = -Int64(target.y)
        var translatedDisplays: [DisplayOrigin] = []
        for display in currentOrigins {
            let x = Int64(display.x) + offsetX
            let y = Int64(display.y) + offsetY
            guard x >= Int64(Int32.min),
                  x <= Int64(Int32.max),
                  y >= Int64(Int32.min),
                  y <= Int64(Int32.max) else {
                return nil
            }

            translatedDisplays.append(DisplayOrigin(
                identifier: display.identifier,
                x: Int32(x),
                y: Int32(y)
            ))
        }
        return translatedDisplays
    }
}

@MainActor
protocol DisplayPrimarySystem: AnyObject {
    func snapshots() -> [DisplayPrimarySnapshot]
    func mainDisplayIdentifier() -> String?
    func apply(origins: [DisplayOrigin]) -> Bool
}

@MainActor
protocol DisplayMonitoring: AnyObject {
    var isPresent: Bool { get }
    var onChange: ((Bool) -> Void)? { get set }
}

@MainActor
final class DisplayMonitor: DisplayMonitoring {
    var configuredDisplayIdentifier: String? {
        didSet {
            scheduleEvaluation()
        }
    }

    var debounceInterval: TimeInterval
    var onChange: ((Bool) -> Void)?

    private(set) var isPresent = false

    private let primaryDisplaySystem: DisplayPrimarySystem
    private var screenObserver: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?
    private var displayCallbackRegistered = false
    private var primaryHubConfigured = false
    private var primaryHubPresent = false
    private var primaryIsSleeping = false
    private var lastActiveDisplayIdentifiers = Set<String>()
    private var primaryConfigurationInProgress = false
    private var primarySyncPending = false

    init(
        configuredDisplayIdentifier: String?,
        debounceInterval: TimeInterval = 1.5,
        primaryDisplaySystem: DisplayPrimarySystem? = nil
    ) {
        self.configuredDisplayIdentifier = configuredDisplayIdentifier
        self.debounceInterval = debounceInterval
        self.primaryDisplaySystem = primaryDisplaySystem ?? CoreGraphicsDisplayPrimarySystem()
    }

    func updatePrimaryHubSignal(configured: Bool, present: Bool) {
        primaryHubConfigured = configured
        primaryHubPresent = present
        synchronizePrimaryDisplay()
    }

    func setPrimaryDisplaySleeping(_ sleeping: Bool) {
        primaryIsSleeping = sleeping
        guard !sleeping else { return }
        synchronizePrimaryDisplay()
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
        let activeDisplayIdentifiers = Set(
            primaryDisplaySystem.snapshots()
                .filter { $0.isActive }
                .map(\.identifier)
        )
        let activeDisplaysChanged = activeDisplayIdentifiers != lastActiveDisplayIdentifiers
        lastActiveDisplayIdentifiers = activeDisplayIdentifiers
        let newValue = configuredDisplayID() != nil
        let displayPresenceChanged = newValue != isPresent

        if displayPresenceChanged {
            isPresent = newValue

            if notify {
                let configured = configuredDisplayIdentifier ?? "none"
                GetKbdLog.event(
                    newValue ? "monitor.connected" : "monitor.disconnected",
                    "configured=\(configured)"
                )
                onChange?(newValue)
            }
        }

        if notify, (activeDisplaysChanged || displayPresenceChanged) {
            synchronizePrimaryDisplay()
        }
    }

    private func synchronizePrimaryDisplay() {
        guard !primaryIsSleeping,
              primaryHubConfigured,
              let configuredDisplayIdentifier else {
            return
        }

        guard !primaryConfigurationInProgress else {
            primarySyncPending = true
            return
        }

        let displays = primaryDisplaySystem.snapshots()
        guard !displays.contains(where: { $0.isMirrored }),
              let targetIdentifier = DisplayPrimaryPlanner.targetIdentifier(
                  configuredDisplayIdentifier: configuredDisplayIdentifier,
                  hubConfigured: primaryHubConfigured,
                  hubPresent: primaryHubPresent,
                  isSleeping: primaryIsSleeping,
                  displays: displays
              ),
              let mainDisplayIdentifier = primaryDisplaySystem.mainDisplayIdentifier(),
              targetIdentifier != mainDisplayIdentifier,
              let origins = DisplayPrimaryPlanner.translatedOrigins(
                  targetIdentifier: targetIdentifier,
                  displays: displays
              ) else {
            return
        }

        primaryConfigurationInProgress = true
        let succeeded = primaryDisplaySystem.apply(origins: origins)
        primaryConfigurationInProgress = false

        if succeeded,
           primaryDisplaySystem.mainDisplayIdentifier() == targetIdentifier {
            GetKbdLog.event("display.primary.set", targetIdentifier)
        } else {
            GetKbdLog.error(
                "display.primary.failed",
                succeeded
                    ? "The requested display did not become primary"
                    : "Unable to apply primary-display configuration"
            )
        }

        let shouldSynchronizeAgain = primarySyncPending
        primarySyncPending = false
        if shouldSynchronizeAgain {
            synchronizePrimaryDisplay()
        }
    }

    private func configuredDisplayID() -> CGDirectDisplayID? {
        configuredDisplayID(in: Self.currentOnlineDisplayIDs())
    }

    private func configuredDisplayID(in displayIDs: [CGDirectDisplayID]) -> CGDirectDisplayID? {
        guard let configuredDisplayIdentifier else { return nil }
        return displayIDs.first {
            Self.identifier(for: $0) == configuredDisplayIdentifier
        }
    }

    nonisolated static func currentOnlineDisplayIDs() -> [CGDirectDisplayID] {
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

    nonisolated static func identifier(for displayID: CGDirectDisplayID) -> String {
        if let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(displayID) {
            let uuid = unmanagedUUID.takeRetainedValue()
            return CFUUIDCreateString(nil, uuid) as String
        }

        return "display-\(CGDisplayVendorNumber(displayID))-\(CGDisplayModelNumber(displayID))-\(CGDisplaySerialNumber(displayID))"
    }
}

@MainActor
private final class CoreGraphicsDisplayPrimarySystem: DisplayPrimarySystem {
    func snapshots() -> [DisplayPrimarySnapshot] {
        DisplayMonitor.currentOnlineDisplayIDs().map { displayID in
            let isActive = CGDisplayIsActive(displayID) != 0
            let bounds = CGDisplayBounds(displayID)
            return DisplayPrimarySnapshot(
                identifier: DisplayMonitor.identifier(for: displayID),
                isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
                isOnline: true,
                isActive: isActive,
                originX: isActive ? Int32(bounds.origin.x.rounded()) : nil,
                originY: isActive ? Int32(bounds.origin.y.rounded()) : nil,
                isMirrored: CGDisplayIsInMirrorSet(displayID) != 0
            )
        }
    }

    func mainDisplayIdentifier() -> String? {
        let mainDisplayID = CGMainDisplayID()
        guard DisplayMonitor.currentOnlineDisplayIDs().contains(mainDisplayID) else {
            return nil
        }
        return DisplayMonitor.identifier(for: mainDisplayID)
    }

    func apply(origins: [DisplayOrigin]) -> Bool {
        let currentDisplays = Dictionary(
            snapshots().compactMap { display -> (String, DisplayPrimarySnapshot)? in
                guard display.isActive else { return nil }
                return (display.identifier, display)
            },
            uniquingKeysWith: { first, _ in first }
        )
        guard origins.allSatisfy({ origin in
            guard let display = currentDisplays[origin.identifier],
                  display.isActive,
                  display.originX != nil,
                  display.originY != nil else {
                return false
            }
            return true
        }) else {
            return false
        }

        let changes = origins.filter { origin in
            guard let display = currentDisplays[origin.identifier],
                  let currentX = display.originX,
                  let currentY = display.originY else {
                return false
            }
            return currentX != origin.x || currentY != origin.y
        }
        guard !changes.isEmpty else { return true }

        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success,
              let configuration else {
            return false
        }

        let displayIDs = Dictionary(
            DisplayMonitor.currentOnlineDisplayIDs().map {
                (DisplayMonitor.identifier(for: $0), $0)
            },
            uniquingKeysWith: { first, _ in first }
        )

        for change in changes {
            guard let displayID = displayIDs[change.identifier] else {
                _ = CGCancelDisplayConfiguration(configuration)
                return false
            }

            let result = CGConfigureDisplayOrigin(
                configuration,
                displayID,
                change.x,
                change.y
            )
            guard result == .success else {
                _ = CGCancelDisplayConfiguration(configuration)
                return false
            }
        }

        return CGCompleteDisplayConfiguration(configuration, .forAppOnly) == .success
    }
}
