import Foundation
import ServiceManagement

@MainActor
enum LoginItemController {
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            GetKbdLog.error("login-item.update.failed", error.localizedDescription)
            return false
        }
    }

    static func statusDescription() -> String {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            return "Not registered"
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Requires approval in System Settings"
        case .notFound:
            return "App bundle not found"
        @unknown default:
            return "Unknown"
        }
    }
}
