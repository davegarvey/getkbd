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

    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }
}
