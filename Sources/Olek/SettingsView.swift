import AppKit
import OlekCore
import SwiftUI
import UserNotifications

/// While any of Olek's windows is open it behaves like a normal app: Dock icon, Cmd-Tab, and a
/// menu bar with Edit and Window commands. With none open it is a menu bar extra again.
@MainActor
private enum WindowPresence {
    static var openCount = 0

    static func opened() {
        openCount += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func closed() {
        openCount = max(0, openCount - 1)
        if openCount == 0 { NSApp.setActivationPolicy(.accessory) }
    }
}

extension View {
    func regularAppWhileVisible() -> some View {
        onAppear { WindowPresence.opened() }
            .onDisappear { WindowPresence.closed() }
    }
}

struct SettingsView: View {
    let model: TrackingController

    var body: some View {
        TabView {
            RemindersSettings(model: model)
                .tabItem { Label("Reminders", systemImage: "bell") }
        }
        .frame(width: 520, height: 640)
        .regularAppWhileVisible()
    }
}

private struct RemindersSettings: View {
    let model: TrackingController
    @State private var authorization: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section("Idle while tracking") {
                Toggle("Ask whether I'm still working when my Mac is idle", isOn: binding(\.idleReminderEnabled))
                Stepper(value: binding(\.idleThresholdMinutes), in: 5...120, step: 5) {
                    Text("After \(minutes(model.reminderSettings.idleThresholdMinutes)) without input")
                }
                .disabled(!model.reminderSettings.idleReminderEnabled)
            }

            Section {
                Toggle("Suggest starting when I use my Mac without tracking", isOn: binding(\.activeReminderEnabled))
                Stepper(value: binding(\.activeThresholdMinutes), in: 2...60, step: 1) {
                    Text("After \(minutes(model.reminderSettings.activeThresholdMinutes)) of use")
                }
                .disabled(!model.reminderSettings.activeReminderEnabled)
            } header: {
                Text("Active while not tracking")
            } footer: {
                Text("Only on scheduled workdays, until the day's target is met. After you stop tracking, Olek waits until you have been away before suggesting again.")
                    .foregroundStyle(.secondary)
            }

            Section("Repeats") {
                Stepper(value: binding(\.snoozeMinutes), in: 5...120, step: 5) {
                    Text("\"Remind Me Later\" waits \(minutes(model.reminderSettings.snoozeMinutes))")
                }
                Stepper(value: binding(\.minimumSpacingMinutes), in: 5...240, step: 5) {
                    Text("At most one reminder of each kind every \(minutes(model.reminderSettings.minimumSpacingMinutes))")
                }
            }

            Section {
                Stepper(value: binding(\.autoStopHours), in: 1...24) {
                    Text("Stop tracking after \(hours(model.reminderSettings.autoStopHours)) of sleep or downtime")
                }
            } header: {
                Text("Sleep and restarts")
            } footer: {
                Text("Shorter gaps keep the session running and ask whether you were working. Gaps under the idle time above are ignored.")
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                LabeledContent("Permission") {
                    Text(authorizationText)
                }
                if authorization == .denied {
                    Button("Open Notification Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                }
                Text("Without notifications, reminders still appear in the menu bar popover and the menu bar icon changes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            await model.notifications.refreshAuthorization()
            authorization = model.notifications.authorization
        }
    }

    // Plain English plurals for now; a string catalog takes over once Estonian is added.
    private func minutes(_ n: Int) -> String { n == 1 ? "1 minute" : "\(n) minutes" }
    private func hours(_ n: Int) -> String { n == 1 ? "1 hour" : "\(n) hours" }

    private var authorizationText: String {
        switch authorization {
        case .authorized, .provisional: String(localized: "Allowed")
        case .denied: String(localized: "Not allowed")
        default: String(localized: "Asked the first time you start tracking")
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<ReminderSettings, T>) -> Binding<T> {
        Binding(
            get: { model.reminderSettings[keyPath: keyPath] },
            set: { value in
                var settings = model.reminderSettings
                settings[keyPath: keyPath] = value
                model.updateReminderSettings(settings)
            }
        )
    }
}
