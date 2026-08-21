import Foundation
import ServiceManagement

enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func enable() throws {
        do {
            try SMAppService.mainApp.register()
        } catch {
            let message = "Auto-start requires Wallps to live in the Applications folder. "
                + "Move Wallps.app into /Applications and try again. (\(error.localizedDescription))"
            throw LoginItemError.message(message)
        }
    }

    static func disable() throws {
        try SMAppService.mainApp.unregister()
    }
}

private enum LoginItemError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}