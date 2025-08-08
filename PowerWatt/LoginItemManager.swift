import Foundation
import ServiceManagement

enum LoginItemManager {
    // Requires a helper login item or the app itself with appropriate capabilities on macOS 13+
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return false
        }
    }

    @discardableResult
    static func enable() throws -> Bool {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            try service.register()
            return true
        } else {
            return false
        }
    }

    @discardableResult
    static func disable() throws -> Bool {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            try service.unregister()
            return true
        } else {
            return false
        }
    }
}


