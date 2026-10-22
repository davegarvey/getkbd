import Foundation

enum MonitorAction: Equatable {
    case switchToOtherMac
    case switchToThisMac
}

enum MenuAction: Equatable {
    case release
    case get
    case retry
    case tryNow
    case enableBluetooth
    case bluetoothSettings
    case finishSetup
}

enum BluetoothActivationState {
    case idle
    case enabling
    case failed
}

/// The menu's single state line, the keyboard action that fits it, and an optional
/// monitor action.
struct MenuStatus: Equatable {
    let title: String
    let action: MenuAction?
    var monitorAction: MonitorAction?

    init(title: String, action: MenuAction?, monitorAction: MonitorAction? = nil) {
        self.title = title
        self.action = action
        self.monitorAction = monitorAction
    }

    static func make(
        settings: AppSettings,
        snapshot: OwnershipSnapshot,
        desiredState: DesiredKeyboardState?,
        currentDisplayIdentifier: String? = nil,
        monitorControlAvailable: Bool = false,
        bluetoothActivation: BluetoothActivationState = .idle
    ) -> MenuStatus {
        var status = keyboardStatus(settings: settings, snapshot: snapshot, desiredState: desiredState, bluetoothActivation: bluetoothActivation)
        // Without a recognised identity, the selected display's own inputs apply.
        status.monitorAction = monitorAction(
            settings: settings,
            inputs: settings.monitorInputs(for: currentDisplayIdentifier ?? settings.selectedDisplay?.identifier),
            snapshot: snapshot,
            monitorControlAvailable: monitorControlAvailable
        )
        return status
    }

    private static func monitorAction(
        settings: AppSettings,
        inputs: LearnedMonitorInputs?,
        snapshot: OwnershipSnapshot,
        monitorControlAvailable: Bool
    ) -> MonitorAction? {
        // Keyboard operations do not hide the action: switching does not depend on
        // Bluetooth, and a hub change during a claim is reconciled once it finishes.
        guard monitorControlAvailable,
              !settings.needsOnboarding,
              snapshot.monitorPresent,
              let inputs else {
            return nil
        }

        if snapshot.usbHubPresent {
            return inputs.otherMac == nil ? nil : .switchToOtherMac
        }
        return inputs.thisMac == nil ? nil : .switchToThisMac
    }

    private static func keyboardStatus(
        settings: AppSettings,
        snapshot: OwnershipSnapshot,
        desiredState: DesiredKeyboardState?,
        bluetoothActivation: BluetoothActivationState
    ) -> MenuStatus {
        if snapshot.bluetoothAvailability != .poweredOn {
            switch bluetoothActivation {
            case .enabling:
                return MenuStatus(title: "Turning Bluetooth on…", action: nil)
            case .failed:
                return MenuStatus(title: "Couldn’t turn Bluetooth on", action: .bluetoothSettings)
            case .idle where snapshot.bluetoothAvailability == .poweredOff && snapshot.keyboardPaired:
                return MenuStatus(title: "Bluetooth is off, so the keyboard can’t be released", action: .enableBluetooth)
            case .idle:
                return MenuStatus(title: snapshot.bluetoothAvailability.title,
                                  action: snapshot.bluetoothAvailability == .poweredOff ? .enableBluetooth : .bluetoothSettings)
            }
        }

        if settings.needsOnboarding {
            return MenuStatus(title: "Setup isn’t finished", action: .finishSetup)
        }

        if snapshot.isRetryingClaim {
            // This Mac cannot tell why the keyboard does not answer, so name the step that
            // helps in most cases rather than a cause.
            return MenuStatus(title: "Keyboard isn’t answering. Switch it off and on, then choose Try Now.", action: .tryNow)
        }

        switch snapshot.keyboardState {
        case .connecting:
            return MenuStatus(title: "Connecting keyboard…", action: .tryNow)
        case .disconnecting:
            return MenuStatus(title: "Releasing keyboard…", action: nil)
        default:
            break
        }

        if snapshot.isBusy {
            return desiredState == .disconnected
                ? MenuStatus(title: "Releasing keyboard…", action: nil)
                : MenuStatus(title: "Connecting keyboard…", action: .tryNow)
        }

        if snapshot.keyboardState == .failed {
            let title = desiredState == .disconnected
                ? "Couldn’t release the keyboard"
                : "Couldn’t connect the keyboard"
            return MenuStatus(title: title, action: .retry)
        }

        if snapshot.keyboardState == .connectedLocal {
            return MenuStatus(title: "Keyboard connected to this Mac", action: .release)
        }

        if !snapshot.monitorPresent {
            return MenuStatus(title: "Monitor not connected", action: .get)
        }

        if snapshot.usbHubPresent {
            return MenuStatus(title: "Keyboard not connected", action: .get)
        }

        return MenuStatus(title: "Monitor is showing your other Mac", action: nil)
    }
}
