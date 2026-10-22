import Foundation

func normalizedBluetoothIdentifier(_ identifier: String) -> String {
    identifier
        .filter { $0 != ":" && $0 != "-" }
        .lowercased()
}

enum BluetoothAvailability: Equatable, Sendable {
    case poweredOn
    case poweredOff
    case unavailable

    var title: String {
        self == .poweredOff ? "Bluetooth is off" : "Bluetooth is unavailable"
    }
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

/// One way the monitor is connected to this Mac. macOS gives a monitor a different
/// display identity for each cable or input it is connected through, and each input
/// can expose its own USB hubs and input numbers.
struct MonitorConnection: Codable, Equatable, Sendable {
    let displayIdentifier: String
    var usbHubs: [USBHubDescriptor]
    var inputs: LearnedMonitorInputs?

    init(displayIdentifier: String, usbHubs: [USBHubDescriptor] = [], inputs: LearnedMonitorInputs? = nil) {
        self.displayIdentifier = displayIdentifier
        self.usbHubs = usbHubs
        self.inputs = inputs
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var selectedKeyboard: KeyboardDescriptor?
    var selectedDisplay: DisplayDescriptor?
    var monitorConnections: [MonitorConnection]
    var switchMainDisplay: Bool
    var launchAtLogin: Bool

    init(
        selectedKeyboard: KeyboardDescriptor?,
        selectedDisplay: DisplayDescriptor?,
        monitorConnections: [MonitorConnection] = [],
        switchMainDisplay: Bool,
        launchAtLogin: Bool
    ) {
        self.selectedKeyboard = selectedKeyboard
        self.selectedDisplay = selectedDisplay
        self.monitorConnections = monitorConnections
        self.switchMainDisplay = switchMainDisplay
        self.launchAtLogin = launchAtLogin
    }

    static let initial = AppSettings(
        selectedKeyboard: nil,
        selectedDisplay: nil,
        switchMainDisplay: true,
        launchAtLogin: true
    )

    var needsOnboarding: Bool {
        selectedKeyboard == nil ||
            selectedDisplay == nil ||
            selectedUSBHubs.isEmpty
    }

    /// The hubs of every connection. Hubs of other connections are unreachable through
    /// the current cable, so any of them being present means the monitor shows this Mac.
    var selectedUSBHubs: [USBHubDescriptor] {
        var seen = Set<String>()
        return monitorConnections
            .flatMap(\.usbHubs)
            .filter { seen.insert($0.identifier).inserted }
    }

    var selectedUSBHubIdentifiers: Set<String> {
        Set(selectedUSBHubs.map(\.identifier))
    }

    var monitorIdentity: MonitorIdentity? {
        guard let selectedDisplay else { return nil }
        return MonitorIdentity(
            name: selectedDisplay.name,
            knownIdentifiers: Set(monitorConnections.map(\.displayIdentifier))
                .union([selectedDisplay.identifier])
        )
    }

    func connection(for displayIdentifier: String?) -> MonitorConnection? {
        monitorConnections.first { $0.displayIdentifier == displayIdentifier }
    }

    /// Learned inputs for a connection of the selected display.
    func monitorInputs(for displayIdentifier: String?) -> LearnedMonitorInputs? {
        guard let inputs = connection(for: displayIdentifier)?.inputs,
              inputs.displayIdentifier == displayIdentifier else {
            return nil
        }
        return inputs
    }

    mutating func addConnection(displayIdentifier: String) {
        guard connection(for: displayIdentifier) == nil else { return }
        monitorConnections.append(MonitorConnection(displayIdentifier: displayIdentifier))
    }

    mutating func setUSBHubs(_ hubs: [USBHubDescriptor], for displayIdentifier: String) {
        updateConnection(displayIdentifier) { $0.usbHubs = hubs }
    }

    mutating func setMonitorInputs(_ inputs: LearnedMonitorInputs) {
        updateConnection(inputs.displayIdentifier) { $0.inputs = inputs }
    }

    private mutating func updateConnection(_ displayIdentifier: String, _ update: (inout MonitorConnection) -> Void) {
        addConnection(displayIdentifier: displayIdentifier)
        guard let index = monitorConnections.firstIndex(where: { $0.displayIdentifier == displayIdentifier }) else { return }
        update(&monitorConnections[index])
    }

    private enum CodingKeys: String, CodingKey {
        case selectedKeyboard
        case selectedDisplay
        case monitorConnections
        // Written alongside the connections so that earlier builds keep a working selection.
        case legacySelectedUSBHubs = "selectedUSBHubs"
        case legacySelectedUSBHub = "selectedUSBHub"
        case legacyMonitorInputs = "monitorInputs"
        case switchMainDisplay
        case launchAtLogin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let selectedDisplay = try container.decodeIfPresent(DisplayDescriptor.self, forKey: .selectedDisplay)
        var connections = try container.decodeIfPresent([MonitorConnection].self, forKey: .monitorConnections)
        if connections == nil, let selectedDisplay {
            let hubs = try container.decodeIfPresent([USBHubDescriptor].self, forKey: .legacySelectedUSBHubs)
            let legacyHub = try container.decodeIfPresent(USBHubDescriptor.self, forKey: .legacySelectedUSBHub)
            let inputs = try? container.decodeIfPresent(LearnedMonitorInputs.self, forKey: .legacyMonitorInputs)
            connections = [MonitorConnection(
                displayIdentifier: selectedDisplay.identifier,
                usbHubs: hubs ?? legacyHub.map { [$0] } ?? [],
                inputs: inputs?.displayIdentifier == selectedDisplay.identifier ? inputs : nil
            )]
        }
        self.init(
            selectedKeyboard: try container.decodeIfPresent(KeyboardDescriptor.self, forKey: .selectedKeyboard),
            selectedDisplay: selectedDisplay,
            monitorConnections: connections ?? [],
            switchMainDisplay: try container.decodeIfPresent(Bool.self, forKey: .switchMainDisplay) ?? true,
            launchAtLogin: try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(selectedKeyboard, forKey: .selectedKeyboard)
        try container.encodeIfPresent(selectedDisplay, forKey: .selectedDisplay)
        try container.encode(monitorConnections, forKey: .monitorConnections)
        try container.encode(selectedUSBHubs, forKey: .legacySelectedUSBHubs)
        try container.encodeIfPresent(selectedUSBHubs.first, forKey: .legacySelectedUSBHub)
        try container.encodeIfPresent(monitorInputs(for: selectedDisplay?.identifier), forKey: .legacyMonitorInputs)
        try container.encode(switchMainDisplay, forKey: .switchMainDisplay)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
    }
}

/// The selected monitor and the display identities it has been seen with.
struct MonitorIdentity: Equatable, Sendable {
    let name: String
    let knownIdentifiers: Set<String>

    /// The online identifier of the monitor: a known identity, or otherwise the only
    /// external display with the monitor's name, which is a new connection of it.
    func identifier(among displays: [DisplayDescriptor]) -> String? {
        let external = displays.filter { !$0.isBuiltIn }
        if let known = external.first(where: { knownIdentifiers.contains($0.identifier) }) {
            return known.identifier
        }
        let named = external.filter { $0.name == name }
        return named.count == 1 ? named[0].identifier : nil
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
    let bluetoothAvailability: BluetoothAvailability
    let ownershipReason: OwnershipReason
    let monitorPresent: Bool
    let usbHubPresent: Bool
    let isBusy: Bool
    let errorMessage: String?
    /// An automatic claim has failed and getkbd is waiting to retry it or retrying it.
    let isRetryingClaim: Bool

    init(
        keyboardState: KeyboardConnectionState,
        ownershipReason: OwnershipReason,
        monitorPresent: Bool,
        usbHubPresent: Bool,
        isBusy: Bool,
        errorMessage: String?,
        bluetoothAvailability: BluetoothAvailability = .poweredOn,
        isRetryingClaim: Bool = false
    ) {
        self.bluetoothAvailability = bluetoothAvailability
        self.isRetryingClaim = isRetryingClaim
        self.keyboardState = keyboardState
        self.ownershipReason = ownershipReason
        self.monitorPresent = monitorPresent
        self.usbHubPresent = usbHubPresent
        self.isBusy = isBusy
        self.errorMessage = errorMessage
    }
}
