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
/// display identity for each cable or input it is connected through, and the input
/// numbers that belong to each Mac change with it.
struct MonitorConnection: Codable, Equatable, Sendable {
    let displayIdentifier: String
    var inputs: LearnedMonitorInputs?

    init(displayIdentifier: String, inputs: LearnedMonitorInputs? = nil) {
        self.displayIdentifier = displayIdentifier
        self.inputs = inputs
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var selectedKeyboard: KeyboardDescriptor?
    var selectedDisplay: DisplayDescriptor?
    var selectedUSBHubs: [USBHubDescriptor]
    var monitorConnections: [MonitorConnection]
    var switchMainDisplay: Bool
    var launchAtLogin: Bool

    init(
        selectedKeyboard: KeyboardDescriptor?,
        selectedDisplay: DisplayDescriptor?,
        selectedUSBHubs: [USBHubDescriptor],
        monitorConnections: [MonitorConnection] = [],
        switchMainDisplay: Bool,
        launchAtLogin: Bool
    ) {
        self.selectedKeyboard = selectedKeyboard
        self.selectedDisplay = selectedDisplay
        self.selectedUSBHubs = selectedUSBHubs
        self.monitorConnections = monitorConnections
        self.switchMainDisplay = switchMainDisplay
        self.launchAtLogin = launchAtLogin
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

    /// Records inputs for a connection. The monitor has the same two inputs on every
    /// connection, so one known input completes the pair from another connection.
    mutating func setMonitorInputs(_ inputs: LearnedMonitorInputs) {
        let others = monitorConnections.compactMap(\.inputs).filter {
            $0.displayIdentifier != inputs.displayIdentifier
        }
        let inputs = inputs.completed(from: others)
        addConnection(displayIdentifier: inputs.displayIdentifier)
        guard let index = monitorConnections.firstIndex(where: {
            $0.displayIdentifier == inputs.displayIdentifier
        }) else { return }
        monitorConnections[index].inputs = inputs
    }

    private enum CodingKeys: String, CodingKey {
        case selectedKeyboard
        case selectedDisplay
        case selectedUSBHubs
        case monitorConnections
        // Written alongside the group and connections so that earlier builds keep a working selection.
        case legacySelectedUSBHub = "selectedUSBHub"
        case legacyMonitorInputs = "monitorInputs"
        case switchMainDisplay
        case launchAtLogin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let selectedDisplay = try container.decodeIfPresent(DisplayDescriptor.self, forKey: .selectedDisplay)
        let hubs = try container.decodeIfPresent([USBHubDescriptor].self, forKey: .selectedUSBHubs)
        let legacyHub = try container.decodeIfPresent(USBHubDescriptor.self, forKey: .legacySelectedUSBHub)
        var connections = try? container.decodeIfPresent([MonitorConnection].self, forKey: .monitorConnections)
        if connections == nil, let selectedDisplay {
            let inputs = try? container.decodeIfPresent(LearnedMonitorInputs.self, forKey: .legacyMonitorInputs)
            connections = [MonitorConnection(
                displayIdentifier: selectedDisplay.identifier,
                inputs: inputs?.displayIdentifier == selectedDisplay.identifier ? inputs : nil
            )]
        }
        self.init(
            selectedKeyboard: try container.decodeIfPresent(KeyboardDescriptor.self, forKey: .selectedKeyboard),
            selectedDisplay: selectedDisplay,
            selectedUSBHubs: hubs ?? legacyHub.map { [$0] } ?? [],
            monitorConnections: connections ?? [],
            switchMainDisplay: try container.decodeIfPresent(Bool.self, forKey: .switchMainDisplay) ?? true,
            launchAtLogin: try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(selectedKeyboard, forKey: .selectedKeyboard)
        try container.encodeIfPresent(selectedDisplay, forKey: .selectedDisplay)
        try container.encode(selectedUSBHubs, forKey: .selectedUSBHubs)
        try container.encode(monitorConnections, forKey: .monitorConnections)
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

    /// Fills a missing input from another connection whose pair contains the known one.
    func completed(from others: [LearnedMonitorInputs]) -> LearnedMonitorInputs {
        var inputs = self
        for other in others {
            guard let first = other.thisMac, let second = other.otherMac else { continue }
            if let thisMac, inputs.otherMac == nil, [first, second].contains(thisMac) {
                inputs.otherMac = thisMac == first ? second : first
            }
            if let otherMac, inputs.thisMac == nil, [first, second].contains(otherMac) {
                inputs.thisMac = otherMac == first ? second : first
            }
        }
        return inputs
    }

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
