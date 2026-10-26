import Foundation
import ServiceManagement

@MainActor
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// The login item points at the app's current path, so it breaks if the app is moved later.
    static var isInstalled: Bool {
        let path = Bundle.main.bundleURL.path
        let userApps = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications").path
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApps + "/")
    }
}
