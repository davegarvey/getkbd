import Foundation

func normalizedBluetoothIdentifier(_ identifier: String) -> String {
    identifier
        .filter { $0 != ":" && $0 != "-" }
        .lowercased()
}

enum KeyboardConnectionState: String, Codable, Equatable, Sendable {
    case disconnected
    case connecting
    case connectedLocal
    case disconnecting
    case failed
    case unknown

    var menuTitle: String {
        switch self {
        case .disconnected:
            return "Not connected"
        case .connecting:
            return "Connecting..."
        case .connectedLocal:
            return "Connected to this Mac"
        case .disconnecting:
            return "Releasing..."
        case .failed:
            return "Unable to switch keyboard"
        case .unknown:
            return "Not configured"
        }
    }
}

enum OwnershipReason: String, Codable, Equatable, Sendable {
    case usbHub
    case manual
    case existing
    case none

    var menuTitle: String {
        switch self {
        case .usbHub: return "KVM USB hub"
        case .manual: return "Manual"
        case .existing: return "Existing connection"
        case .none: return "None"
        }
    }
}

enum DesiredKeyboardState: String, Equatable, Sendable {
    case connected
    case disconnected
}

struct KeyboardDescriptor: Codable, Equatable, Hashable, Identifiable, Sendable {
    let identifier: String
    let name: String

    var id: String { identifier }
}

struct DisplayDescriptor: Codable, Equatable, Hashable, Identifiable, Sendable {
    let identifier: String
    let name: String
    let isBuiltIn: Bool

    var id: String { identifier }
}

struct USBHubDescriptor: Codable, Equatable, Hashable, Identifiable, Sendable {
    let identifier: String
    let name: String
    let manufacturer: String
    let vendorID: Int
    let productID: Int

    init(identifier: String, name: String, manufacturer: String, vendorID: Int, productID: Int) {
        self.identifier = identifier
        self.name = name
        self.manufacturer = manufacturer
        self.vendorID = vendorID
        self.productID = productID
    }

    var id: String { identifier }

    var menuTitle: String {
        let vendor = manufacturer.isEmpty ? "USB" : manufacturer
        let identifier = String(format: "%04X:%04X", vendorID, productID)
        return "\(vendor) \(name) (\(identifier))"
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var selectedKeyboard: KeyboardDescriptor?
    var selectedDisplay: DisplayDescriptor?
    var selectedUSBHubs: [USBHubDescriptor]
    var switchMainDisplay: Bool
    var launchAtLogin: Bool
    var monitorInputs: LearnedMonitorInputs?

    init(
        selectedKeyboard: KeyboardDescriptor?,
        selectedDisplay: DisplayDescriptor?,
        selectedUSBHubs: [USBHubDescriptor],
        switchMainDisplay: Bool,
        launchAtLogin: Bool,
        monitorInputs: LearnedMonitorInputs? = nil
    ) {
        self.selectedKeyboard = selectedKeyboard
        self.selectedDisplay = selectedDisplay
        self.selectedUSBHubs = selectedUSBHubs
        self.switchMainDisplay = switchMainDisplay
        self.launchAtLogin = launchAtLogin
        self.monitorInputs = monitorInputs
    }

    static let initial = AppSettings(
        selectedKeyboard: nil,
        selectedDisplay: nil,
        selectedUSBHubs: [],
        switchMainDisplay: true,
        launchAtLogin: true
    )

    var needsOnboarding: Bool {
        selectedKeyboard == nil ||
            selectedDisplay == nil ||
            selectedUSBHubs.isEmpty
    }

    /// Learned inputs for the selected display, ignoring any learned for another display.
    var currentMonitorInputs: LearnedMonitorInputs? {
        guard let monitorInputs,
              monitorInputs.displayIdentifier == selectedDisplay?.identifier else {
            return nil
        }
        return monitorInputs
    }

    var selectedUSBHubIdentifiers: Set<String> {
        Set(selectedUSBHubs.map(\.identifier))
    }

    private enum CodingKeys: String, CodingKey {
        case selectedKeyboard
        case selectedDisplay
        case selectedUSBHubs
        // Written alongside the group so that earlier builds keep a working selection.
        case legacySelectedUSBHub = "selectedUSBHub"
        case switchMainDisplay
        case launchAtLogin
        case monitorInputs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hubs = try container.decodeIfPresent([USBHubDescriptor].self, forKey: .selectedUSBHubs)
        let legacyHub = try container.decodeIfPresent(USBHubDescriptor.self, forKey: .legacySelectedUSBHub)
        self.init(
            selectedKeyboard: try container.decodeIfPresent(KeyboardDescriptor.self, forKey: .selectedKeyboard),
            selectedDisplay: try container.decodeIfPresent(DisplayDescriptor.self, forKey: .selectedDisplay),
            selectedUSBHubs: hubs ?? legacyHub.map { [$0] } ?? [],
            switchMainDisplay: try container.decodeIfPresent(Bool.self, forKey: .switchMainDisplay) ?? true,
            launchAtLogin: try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true,
            monitorInputs: try? container.decodeIfPresent(LearnedMonitorInputs.self, forKey: .monitorInputs)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(selectedKeyboard, forKey: .selectedKeyboard)
        try container.encodeIfPresent(selectedDisplay, forKey: .selectedDisplay)
        try container.encode(selectedUSBHubs, forKey: .selectedUSBHubs)
        try container.encodeIfPresent(selectedUSBHubs.first, forKey: .legacySelectedUSBHub)
        try container.encode(switchMainDisplay, forKey: .switchMainDisplay)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encodeIfPresent(monitorInputs, forKey: .monitorInputs)
    }
}

/// The monitor input numbers learned for each Mac on one display.
struct LearnedMonitorInputs: Codable, Equatable, Sendable {
    let displayIdentifier: String
    var thisMac: Int?
    var otherMac: Int?

    /// Returns the inputs with a new reading recorded, or nil when the reading conflicts
    /// with the other Mac's input and must be discarded.
    static func recording(
        _ value: Int,
        forThisMac isThisMac: Bool,
        displayIdentifier: String,
        into existing: LearnedMonitorInputs?
    ) -> LearnedMonitorInputs? {
        var inputs = LearnedMonitorInputs(displayIdentifier: displayIdentifier)
        if let existing, existing.displayIdentifier == displayIdentifier {
            inputs = existing
        }
        if isThisMac {
            guard inputs.otherMac != value else { return nil }
            inputs.thisMac = value
        } else {
            guard inputs.thisMac != value else { return nil }
            inputs.otherMac = value
        }
        return inputs
    }
}

struct OwnershipSnapshot: Equatable, Sendable {
    let keyboardState: KeyboardConnectionState
    let ownershipReason: OwnershipReason
    let monitorPresent: Bool
    let usbHubPresent: Bool
    let isBusy: Bool
    let errorMessage: String?

    init(
        keyboardState: KeyboardConnectionState,
        ownershipReason: OwnershipReason,
        monitorPresent: Bool,
        usbHubPresent: Bool,
        isBusy: Bool,
        errorMessage: String?
    ) {
        self.keyboardState = keyboardState
        self.ownershipReason = ownershipReason
        self.monitorPresent = monitorPresent
        self.usbHubPresent = usbHubPresent
        self.isBusy = isBusy
        self.errorMessage = errorMessage
    }
}
