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

        Window("History", id: "history") {
            HistoryView(model: appDelegate.controller)
        }
        .defaultSize(width: 920, height: 640)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(model: appDelegate.controller)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = TrackingController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // For README screenshots: open "Olek Dev.app" --args -OlekAppearance dark
        if let style = UserDefaults.standard.string(forKey: "OlekAppearance") {
            NSApp.appearance = NSAppearance(named: style == "dark" ? .darkAqua : .aqua)
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Recording the quit time keeps a quick relaunch from looking like a liveness gap.
        controller.recordHeartbeatNow()
    }
}
