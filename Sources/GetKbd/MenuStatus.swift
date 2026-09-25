import Foundation

enum MonitorAction: Equatable {
    case switchToOtherMac
    case switchToThisMac
}

enum MenuAction: Equatable {
    case release
    case get
    case retry
    case finishSetup
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
        monitorControlAvailable: Bool = false
    ) -> MenuStatus {
        var status = keyboardStatus(settings: settings, snapshot: snapshot, desiredState: desiredState)
        status.monitorAction = monitorAction(
            settings: settings,
            snapshot: snapshot,
            monitorControlAvailable: monitorControlAvailable
        )
        return status
    }

    private static func monitorAction(
        settings: AppSettings,
        snapshot: OwnershipSnapshot,
        monitorControlAvailable: Bool
    ) -> MonitorAction? {
        guard monitorControlAvailable,
              !settings.needsOnboarding,
              !snapshot.isBusy,
              snapshot.keyboardState != .connecting,
              snapshot.keyboardState != .disconnecting,
              snapshot.monitorPresent,
              let inputs = settings.currentMonitorInputs else {
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
        desiredState: DesiredKeyboardState?
    ) -> MenuStatus {
        if settings.needsOnboarding {
            return MenuStatus(title: "Setup isn’t finished", action: .finishSetup)
        }

        switch snapshot.keyboardState {
        case .connecting:
            return MenuStatus(title: "Connecting keyboard…", action: nil)
        case .disconnecting:
            return MenuStatus(title: "Releasing keyboard…", action: nil)
        default:
            break
        }

        if snapshot.isBusy {
            let title = desiredState == .disconnected ? "Releasing keyboard…" : "Connecting keyboard…"
            return MenuStatus(title: title, action: nil)
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
