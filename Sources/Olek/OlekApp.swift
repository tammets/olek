import SwiftUI

@main
struct OlekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: appDelegate.controller)
        } label: {
            MenuBarLabel(model: appDelegate.controller)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = TrackingController()

    func applicationWillTerminate(_ notification: Notification) {
        // Recording the quit time keeps a quick relaunch from looking like a liveness gap.
        controller.recordHeartbeatNow()
    }
}
