import Carbon
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
    case monitor
    case usbHub
    case manual
    case existing
    case none

    var menuTitle: String {
        switch self {
        case .monitor: return "Monitor"
        case .usbHub: return "KVM USB hub"
        case .manual: return "Manual"
        case .existing: return "Existing connection"
        case .none: return "None"
        }
    }
}

enum AutomaticSource: String, Codable, Equatable, Sendable {
    case monitor
    case usbHub
    case off

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "monitor":
            self = .monitor
        case "usbHub", "kvmInput":
            self = .usbHub
        case "off":
            self = .off
        default:
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unknown automatic source \(value)"
            )
        }
    }

    var menuTitle: String {
        switch self {
        case .monitor: return "Monitor connection"
        case .usbHub: return "KVM USB hub connection"
        case .off: return "Manual only"
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

    var id: String { identifier }

    var menuTitle: String {
        let vendor = manufacturer.isEmpty ? "USB" : manufacturer
        let identifier = String(format: "%04X:%04X", vendorID, productID)
        return "\(vendor) \(name) (\(identifier))"
    }
}

struct ShortcutConfiguration: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = ShortcutConfiguration(
        keyCode: UInt32(kVK_ANSI_K),
        modifiers: UInt32(controlKey | optionKey | cmdKey)
    )

    var displayString: String {
        var parts: [String] = []

        if modifiers & UInt32(controlKey) != 0 {
            parts.append("Ctrl")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("Opt")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("Shift")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("Cmd")
        }

        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: "+")
    }

    var keyEquivalent: String {
        let name = Self.keyName(for: keyCode)
        guard name.count == 1 else { return "" }
        return name.lowercased()
    }

    static func keyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case UInt32(kVK_ANSI_A): return "A"
        case UInt32(kVK_ANSI_B): return "B"
        case UInt32(kVK_ANSI_C): return "C"
        case UInt32(kVK_ANSI_D): return "D"
        case UInt32(kVK_ANSI_E): return "E"
        case UInt32(kVK_ANSI_F): return "F"
        case UInt32(kVK_ANSI_G): return "G"
        case UInt32(kVK_ANSI_H): return "H"
        case UInt32(kVK_ANSI_I): return "I"
        case UInt32(kVK_ANSI_J): return "J"
        case UInt32(kVK_ANSI_K): return "K"
        case UInt32(kVK_ANSI_L): return "L"
        case UInt32(kVK_ANSI_M): return "M"
        case UInt32(kVK_ANSI_N): return "N"
        case UInt32(kVK_ANSI_O): return "O"
        case UInt32(kVK_ANSI_P): return "P"
        case UInt32(kVK_ANSI_Q): return "Q"
        case UInt32(kVK_ANSI_R): return "R"
        case UInt32(kVK_ANSI_S): return "S"
        case UInt32(kVK_ANSI_T): return "T"
        case UInt32(kVK_ANSI_U): return "U"
        case UInt32(kVK_ANSI_V): return "V"
        case UInt32(kVK_ANSI_W): return "W"
        case UInt32(kVK_ANSI_X): return "X"
        case UInt32(kVK_ANSI_Y): return "Y"
        case UInt32(kVK_ANSI_Z): return "Z"
        case UInt32(kVK_ANSI_0): return "0"
        case UInt32(kVK_ANSI_1): return "1"
        case UInt32(kVK_ANSI_2): return "2"
        case UInt32(kVK_ANSI_3): return "3"
        case UInt32(kVK_ANSI_4): return "4"
        case UInt32(kVK_ANSI_5): return "5"
        case UInt32(kVK_ANSI_6): return "6"
        case UInt32(kVK_ANSI_7): return "7"
        case UInt32(kVK_ANSI_8): return "8"
        case UInt32(kVK_ANSI_9): return "9"
        case UInt32(kVK_Return): return "Return"
        case UInt32(kVK_Space): return "Space"
        case UInt32(kVK_Tab): return "Tab"
        case UInt32(kVK_Escape): return "Esc"
        default: return "Key \(keyCode)"
        }
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var selectedKeyboard: KeyboardDescriptor?
    var selectedDisplay: DisplayDescriptor?
    var selectedUSBHub: USBHubDescriptor?
    var claimOnMonitorConnect: Bool
    var monitorTakesOwnershipFromManual: Bool
    var releaseOnMonitorDisconnect: Bool
    var releaseBeforeSleep: Bool
    var automaticSource: AutomaticSource
    var shortcut: ShortcutConfiguration
    var launchAtLogin: Bool

    init(
        selectedKeyboard: KeyboardDescriptor?,
        selectedDisplay: DisplayDescriptor?,
        selectedUSBHub: USBHubDescriptor?,
        claimOnMonitorConnect: Bool,
        monitorTakesOwnershipFromManual: Bool,
        releaseOnMonitorDisconnect: Bool,
        releaseBeforeSleep: Bool,
        automaticSource: AutomaticSource,
        shortcut: ShortcutConfiguration,
        launchAtLogin: Bool
    ) {
        self.selectedKeyboard = selectedKeyboard
        self.selectedDisplay = selectedDisplay
        self.selectedUSBHub = selectedUSBHub
        self.claimOnMonitorConnect = claimOnMonitorConnect
        self.monitorTakesOwnershipFromManual = monitorTakesOwnershipFromManual
        self.releaseOnMonitorDisconnect = releaseOnMonitorDisconnect
        self.releaseBeforeSleep = releaseBeforeSleep
        self.automaticSource = automaticSource
        self.shortcut = shortcut
        self.launchAtLogin = launchAtLogin
    }

    static let initial = AppSettings(
        selectedKeyboard: nil,
        selectedDisplay: nil,
        selectedUSBHub: nil,
        claimOnMonitorConnect: true,
        monitorTakesOwnershipFromManual: false,
        releaseOnMonitorDisconnect: true,
        releaseBeforeSleep: true,
        automaticSource: .monitor,
        shortcut: .default,
        launchAtLogin: true
    )

    var needsOnboarding: Bool {
        selectedKeyboard == nil ||
            (automaticSource == .monitor && selectedDisplay == nil) ||
            (automaticSource == .usbHub && (selectedDisplay == nil || selectedUSBHub == nil))
    }

    private enum CodingKeys: String, CodingKey {
        case selectedKeyboard
        case selectedDisplay
        case selectedUSBHub
        case claimOnMonitorConnect
        case monitorTakesOwnershipFromManual
        case releaseOnMonitorDisconnect
        case releaseBeforeSleep
        case automaticSource
        case shortcut
        case launchAtLogin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            selectedKeyboard: try container.decodeIfPresent(KeyboardDescriptor.self, forKey: .selectedKeyboard),
            selectedDisplay: try container.decodeIfPresent(DisplayDescriptor.self, forKey: .selectedDisplay),
            selectedUSBHub: try container.decodeIfPresent(USBHubDescriptor.self, forKey: .selectedUSBHub),
            claimOnMonitorConnect: try container.decode(Bool.self, forKey: .claimOnMonitorConnect),
            monitorTakesOwnershipFromManual: try container.decodeIfPresent(
                Bool.self,
                forKey: .monitorTakesOwnershipFromManual
            ) ?? false,
            releaseOnMonitorDisconnect: try container.decode(Bool.self, forKey: .releaseOnMonitorDisconnect),
            releaseBeforeSleep: try container.decode(Bool.self, forKey: .releaseBeforeSleep),
            automaticSource: try container.decodeIfPresent(AutomaticSource.self, forKey: .automaticSource) ?? .monitor,
            shortcut: try container.decode(ShortcutConfiguration.self, forKey: .shortcut),
            launchAtLogin: try container.decode(Bool.self, forKey: .launchAtLogin)
        )
    }
}

struct AutomaticBehavior: Equatable, Sendable {
    var claimOnMonitorConnect: Bool
    var monitorTakesOwnershipFromManual: Bool
    var releaseOnMonitorDisconnect: Bool
    var releaseBeforeSleep: Bool
    var automaticSource: AutomaticSource = .monitor
}

struct OwnershipSnapshot: Equatable, Sendable {
    let keyboardState: KeyboardConnectionState
    let ownershipReason: OwnershipReason
    let monitorPresent: Bool
    let usbHubPresent: Bool
    let isBusy: Bool
    let errorMessage: String?
}
