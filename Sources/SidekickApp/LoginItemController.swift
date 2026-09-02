import Foundation
import ServiceManagement

protocol LoginItemControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

enum LoginItemError: LocalizedError, Equatable {
    case requiresApproval

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return "请在系统设置中允许 Sidekick 登录时打开"
        }
    }
}

final class SMAppServiceLoginItemController: LoginItemControlling {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .requiresApproval {
                throw LoginItemError.requiresApproval
            }
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }
}
