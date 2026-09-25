import Foundation

enum MenuAction: Equatable {
    case release
    case get
    case retry
    case finishSetup
}

/// The menu's single state line and the one action that fits it.
struct MenuStatus: Equatable {
    let title: String
    let action: MenuAction?

    static func make(
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
