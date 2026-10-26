import AppKit
import OlekCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
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
            GeneralTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            ScheduleTab(model: model)
                .tabItem { Label("Schedule", systemImage: "calendar") }
            RemindersTab(model: model)
                .tabItem { Label("Reminders", systemImage: "bell") }
            DataTab(model: model)
                .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 540, height: 640)
        .environment(\.locale, Locale(identifier: "en_GB"))
        .regularAppWhileVisible()
    }
}

// MARK: - General

private struct GeneralTab: View {
    let model: TrackingController
    @State private var loginStatus = LoginItem.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open Olek at login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: { enabled in
                        do {
                            try LoginItem.setEnabled(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                        loginStatus = LoginItem.status
                    }
                ))
                if !LoginItem.isInstalled {
                    Text("Olek is running from \(Bundle.main.bundleURL.deletingLastPathComponent().path). Move it to Applications before turning this on; the login item stops working if the app is moved later.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if loginStatus == .requiresApproval {
                    Text("macOS needs your approval in System Settings, General, Login Items.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.red)
                }
            }

            Section("Menu bar") {
                Picker("Next to the icon", selection: Binding(
                    get: { model.generalSettings.menuBarText },
                    set: { value in
                        var settings = model.generalSettings
                        settings.menuBarText = value
                        model.updateGeneralSettings(settings)
                    }
                )) {
                    Text("Session time while working").tag(GeneralSettings.MenuBarText.sessionWhileWorking)
                    Text("Today's total").tag(GeneralSettings.MenuBarText.todayTotal)
                    Text("Nothing").tag(GeneralSettings.MenuBarText.iconOnly)
                }
            }

            Section {
                LabeledContent("Version") {
                    Text(versionText).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loginStatus = LoginItem.status }
    }
}

private var versionText: String {
    let info = Bundle.main.infoDictionary ?? [:]
    let version = info["CFBundleShortVersionString"] as? String ?? "?"
    let build = info["CFBundleVersion"] as? String ?? "?"
    return "\(version) (\(build))"
}

// MARK: - Schedule

private struct ScheduleTab: View {
    let model: TrackingController
    @State private var openingText = ""
    @State private var openingInvalid = false

    private static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        Form {
            Section("Weekly schedule") {
                ForEach(Weekday.allCases, id: \.self) { day in
                    let value = model.workSettings.scheduledMinutes(on: day)
                    let hours = value > 0 ? DurationFormat.hoursMinutes(TimeInterval(value * 60)) : String(localized: "Off")
                    Stepper(value: minutes(day), in: 0...(24 * 60), step: 30) {
                        HStack {
                            Text(Self.dayNames[day.rawValue - 1])
                            Spacer()
                            Text(hours).monospacedDigit()
                        }
                    }
                    .accessibilityLabel("\(Self.dayNames[day.rawValue - 1]), \(hours)")
                }
                LabeledContent("Week") {
                    Text(DurationFormat.hoursMinutes(TimeInterval(model.workSettings.minutesByWeekday.reduce(0, +) * 60)))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
            }

            Section {
                Toggle("Estonian public holidays", isOn: setting(\.estonianHolidays))
                Toggle("Shorten the working day before New Year's Day, Independence Day, Victory Day, and Christmas Eve by 3 hours", isOn: setting(\.shortenedDays))
                    .disabled(!model.workSettings.estonianHolidays)
            } header: {
                Text("Holidays")
            } footer: {
                Text("Shortened days follow Employment Contracts Act § 53. Individual days can be changed in History.")
                    .foregroundStyle(.secondary)
            }

            Section {
                DatePicker("Accounting starts", selection: accountingStart, displayedComponents: .date)
                LabeledContent("Opening balance") {
                    TextField("Opening balance", text: $openingText, prompt: Text("e.g. +12:30"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .onChange(of: openingText) { _, text in saveOpening(text) }
                }
                if openingInvalid {
                    Text("Use a form like +12:30, -3h, or 2h 15m.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Balance")
            } footer: {
                Text("The balance counts every day from the accounting start. The opening balance carries over hours from before, for example from another tracking system.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            openingText = DurationFormat.signed(TimeInterval(model.workSettings.openingBalanceMinutes * 60))
        }
    }

    private func update(_ change: (inout WorkSettings) -> Void) {
        var settings = model.workSettings
        change(&settings)
        model.updateWorkSettings(settings)
    }

    private func setting(_ keyPath: WritableKeyPath<WorkSettings, Bool>) -> Binding<Bool> {
        Binding(get: { model.workSettings[keyPath: keyPath] }, set: { value in update { $0[keyPath: keyPath] = value } })
    }

    private func minutes(_ day: Weekday) -> Binding<Int> {
        Binding(
            get: { model.workSettings.scheduledMinutes(on: day) },
            set: { value in update { $0.minutesByWeekday[day.rawValue - 1] = value } }
        )
    }

    private var accountingStart: Binding<Date> {
        let calendar = Calendar.autoupdatingCurrent
        return Binding(
            get: { model.accountingStart.interval(in: calendar).start },
            set: { date in update { $0.accountingStart = LocalDate(date, calendar: calendar) } }
        )
    }

    private func saveOpening(_ text: String) {
        guard let minutes = DurationParse.minutes(text) else {
            openingInvalid = !text.trimmingCharacters(in: .whitespaces).isEmpty
            return
        }
        openingInvalid = false
        if minutes != model.workSettings.openingBalanceMinutes {
            update { $0.openingBalanceMinutes = minutes }
        }
    }
}

// MARK: - Data

private struct DataTab: View {
    let model: TrackingController

    struct PendingRestore: Identifiable {
        let url: URL
        let summary: BackupSummary
        var id: URL { url }
    }

    @State private var message: String?
    @State private var messageIsError = false
    @State private var pendingRestore: PendingRestore?

    var body: some View {
        Form {
            Section {
                Button("Export Sessions as CSV…") {
                    save(text: model.sessionsCSV(), name: "olek-sessions")
                }
                Button("Export Daily Summary as CSV…") {
                    if let csv = model.dailySummaryCSV() { save(text: csv, name: "olek-daily") }
                }
            } header: {
                Text("Export")
            } footer: {
                Text("Times include their UTC offset. The daily summary has expected and worked minutes and the running balance.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Back Up Database…", action: backUp)
                Button("Restore from Backup…", action: chooseRestore)
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(messageIsError ? .red : .secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("A backup is a single file with all sessions, day types, and settings. Restoring first saves your current data to the Backups folder, so it can be undone.")
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                LabeledContent("Data folder") {
                    Text(AppPaths.dataFolder.path)
                        .textSelection(.enabled)
                        .font(.callout)
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.databaseURL])
                }
            }
        }
        .formStyle(.grouped)
        .alert("Replace all data with this backup?", isPresented: Binding(
            get: { pendingRestore != nil },
            set: { if !$0 { pendingRestore = nil } }
        ), presenting: pendingRestore) { pending in
            Button("Restore", role: .destructive) { restore(pending.url) }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(restoreDescription(pending.summary))
        }
    }

    private var today: String { LocalDate(Date(), calendar: .autoupdatingCurrent).description }

    private func save(text: String, name: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(name)-\(today).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            report(String(localized: "Saved \(url.lastPathComponent)."))
        } catch {
            report(error.localizedDescription, isError: true)
        }
    }

    private func backUp() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "sqlite") ?? .data]
        panel.nameFieldStringValue = "olek-backup-\(today).sqlite"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.backup(to: url)
            report(String(localized: "Backed up to \(url.lastPathComponent)."))
        } catch {
            report(error.localizedDescription, isError: true)
        }
    }

    private func chooseRestore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "sqlite") ?? .data, .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            pendingRestore = PendingRestore(url: url, summary: try SessionStore.inspectBackup(at: url))
        } catch {
            report(error.localizedDescription, isError: true)
        }
    }

    private func restore(_ url: URL) {
        do {
            let safety = try model.restore(from: url)
            report(String(localized: "Restored. Your previous data was saved as \(safety.lastPathComponent) in the Backups folder."))
        } catch {
            report(error.localizedDescription, isError: true)
        }
    }

    private func restoreDescription(_ summary: BackupSummary) -> String {
        let calendar = Calendar.autoupdatingCurrent
        guard let first = summary.firstSession, let last = summary.lastSession else {
            return String(localized: "The backup contains no sessions. Your current data is saved to the Backups folder first.")
        }
        let range = DateFormat.range(LocalDate(first, calendar: calendar), LocalDate(last, calendar: calendar))
        return String(localized: "The backup holds \(summary.sessionCount) sessions, \(range). Your current data is saved to the Backups folder first, so this can be undone.")
    }

    private func report(_ text: String, isError: Bool = false) {
        message = text
        messageIsError = isError
    }
}

private struct RemindersTab: View {
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
