import AppKit
import Observation
import OlekCore

enum RecoveryNotice: Equatable {
    /// The Mac slept or Olek was not running for a while; the session kept going.
    case askedAboutGap(sessionID: Int64, from: Date, to: Date)
    /// The gap was long enough that the session was stopped at its start.
    case autoStopped(session: Session, stoppedAt: Date, awayUntil: Date)
}

enum SessionEdge {
    case start, end
}

@MainActor
@Observable
final class TrackingController {
    private(set) var openSession: Session?
    private(set) var latestSession: Session?
    private(set) var overview: Overview?
    private(set) var ledger: Ledger?
    /// Every session ever recorded, oldest first.
    private(set) var allSessions: [Session] = []
    private(set) var now = Date()
    private(set) var notice: RecoveryNotice?
    /// A reminder waiting for an answer, shown in the popover as well as a notification.
    private(set) var reminder: Reminder?
    private(set) var reminderSettings = ReminderSettings()
    private(set) var workSettings = WorkSettings()
    private(set) var generalSettings = GeneralSettings()
    /// The accounting start in effect: the saved one, or the day of first launch.
    private(set) var accountingStart = LocalDate(Date(), calendar: .autoupdatingCurrent)
    private(set) var errorMessage: String?

    var isWorking: Bool { openSession != nil }

    /// The session the quick-adjust buttons act on: the running one, else the most recent.
    var adjustableSession: Session? { openSession ?? latestSession }

    @ObservationIgnored private let store: SessionStore?
    @ObservationIgnored private var policy = RecoveryPolicy()
    @ObservationIgnored private var engine = ReminderEngine(settings: ReminderSettings())
    @ObservationIgnored let notifications = NotificationService()
    @ObservationIgnored private let calendar = Calendar.autoupdatingCurrent
    @ObservationIgnored private var today: LocalDate
    @ObservationIgnored private var workingCalendar: WorkingCalendar?
    @ObservationIgnored private var openingBalance: TimeInterval = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var errorClearTask: Task<Void, Never>?

    private static let tickInterval: TimeInterval = 10
    private static let heartbeatInterval: TimeInterval = 60

    init() {
        today = LocalDate(Date(), calendar: .autoupdatingCurrent)
        do {
            store = try SessionStore(url: AppPaths.databaseURL)
        } catch {
            store = nil
            errorMessage = String(describing: error)
        }
        loadReminderSettings()
        reload()
        checkLiveness()
        startTimer()
        observeSystem()
        notifications.onAction = { [weak self] action, text in self?.handle(action, typedText: text) }
    }

    func sessionDuration(at date: Date) -> TimeInterval? {
        openSession.map { date.timeIntervalSince($0.start) }
    }

    // MARK: Actions

    func toggle() {
        isWorking ? stop() : start()
    }

    func start() {
        start(at: Date())
    }

    func start(at time: Date) {
        perform {
            try $0.start(at: time, now: Date())
            if case .autoStopped = notice { notice = nil }
        }
        if isWorking { trackingDidStart() }
    }

    func stop() {
        stop(at: Date())
    }

    func stop(at time: Date) {
        perform { try $0.stop(at: time, now: Date()) }
        if !isWorking { trackingDidStop() }
    }

    // MARK: Reminders

    func handle(_ action: NotificationService.Action, typedText: String? = nil) {
        switch (action, reminder) {
        case (.continueWorking, _):
            clearReminder()
        case (.stopNow, _):
            clearReminder()
            if isWorking { stop() }
        case (.stopAtIdleStart, .idleWhileTracking(let since)?):
            clearReminder()
            if isWorking { stop(at: since) }
        case (.remindLater, let pending?):
            engine.snooze(pending.kind, now: Date())
            clearReminder()
        case (.startNow, _):
            clearReminder()
            if !isWorking { start() }
        case (.startAtActiveStart, .activeWhileStopped(let since)?):
            clearReminder()
            if !isWorking { start(at: since) }
        case (.startAtTypedTime, _):
            guard let text = typedText, let time = TimeParse.time(text, sameDayAs: Date(), calendar: calendar) else {
                show(message: String(localized: "Could not read \"\(typedText ?? "")\" as a time. Use a form like 9:15."))
                return
            }
            clearReminder()
            if !isWorking { start(at: time) }
        case (.notWorking, _):
            engine.dismissActive()
            clearReminder()
        default:
            // The reminder was already answered elsewhere, e.g. in the popover.
            break
        }
    }

    func updateWorkSettings(_ settings: WorkSettings) {
        perform { try $0.saveWorkSettings(settings) }
    }

    func updateGeneralSettings(_ settings: GeneralSettings) {
        perform { try $0.saveGeneralSettings(settings) }
    }

    // MARK: Data

    func sessionsCSV() -> String {
        CSVExport.sessions(allSessions, timeZone: calendar.timeZone)
    }

    /// From the first recorded day or the accounting start, whichever is earlier, through today.
    func dailySummaryCSV() -> String? {
        guard let ledger else { return nil }
        let firstSession = allSessions.first.map { LocalDate($0.start, calendar: calendar) } ?? today
        return CSVExport.dailySummary(
            ledger: ledger,
            from: min(firstSession, accountingStart),
            through: today,
            openingBalance: openingBalance
        )
    }

    func backup(to url: URL) throws {
        guard let store else { throw SessionError.notFound }
        try store.backup(to: url)
    }

    func restore(from url: URL) throws -> URL {
        let stamp = CSVExport.timestamp(Date(), calendar.timeZone)
            .replacingOccurrences(of: ":", with: "-")
        let safety = AppPaths.backupsFolder.appending(path: "before-restore-\(stamp).sqlite")
        // Whatever was pending refers to sessions that may no longer exist.
        notice = nil
        clearReminder()
        try mutate { try $0.restore(from: url, safetyCopy: safety) }
        loadReminderSettings()
        return safety
    }

    func updateReminderSettings(_ settings: ReminderSettings) {
        perform { try $0.saveReminderSettings(settings) }
        loadReminderSettings()
    }

    private func loadReminderSettings() {
        reminderSettings = (try? store?.reminderSettings()) ?? ReminderSettings()
        engine.settings = reminderSettings
        policy = reminderSettings.recoveryPolicy
    }

    private func trackingDidStart() {
        if case .activeWhileStopped = reminder { clearReminder() }
        notifications.requestAuthorizationIfNeeded()
    }

    private func trackingDidStop() {
        engine.trackingStopped()
        if case .idleWhileTracking = reminder { clearReminder() }
    }

    private func clearReminder() {
        if let reminder { notifications.clear(reminder.kind) }
        reminder = nil
    }

    private func sampleActivity() {
        let workExpected = overview.map { $0.todayWorked < $0.todayPlan.expected } ?? false
        guard let fired = engine.sample(
            now: now,
            idleSeconds: ActivityMonitor.secondsSinceLastInput(),
            isTracking: isWorking,
            workExpected: workExpected
        ) else { return }
        reminder = fired
        notifications.show(fired)
    }

    /// Moves one edge of the adjustable session. Negative minutes move it earlier.
    func adjust(_ edge: SessionEdge, minutes: Int) {
        guard var session = adjustableSession else { return }
        let delta = TimeInterval(minutes * 60)
        switch edge {
        case .start:
            session.start += delta
        case .end:
            guard let end = session.end else { return }
            session.end = end + delta
        }
        perform { try $0.update(session, now: Date()) }
    }

    // MARK: History editing

    /// Throwing variants report validation errors back to the sheet that asked.
    func addSession(start: Date, end: Date, note: String?) throws {
        try mutate { try $0.add(start: start, end: end, note: note, now: Date()) }
    }

    func saveSession(_ session: Session) throws {
        try mutate { try $0.update(session, now: Date()) }
    }

    func insertBreak(in session: Session, from: Date, to: Date) throws {
        try mutate { try $0.insertBreak(sessionID: session.id, from: from, to: to, now: Date()) }
    }

    func deleteSession(_ session: Session) {
        perform { try $0.delete(id: session.id) }
    }

    func setDayOverride(_ override: DayOverride) {
        perform { try $0.setDayOverride(override, now: Date()) }
    }

    func removeDayOverride(on date: LocalDate) {
        perform { try $0.removeDayOverride(on: date) }
    }

    func dayOverride(on date: LocalDate) -> DayOverride? {
        workingCalendar?.overrides[date]
    }

    /// Sessions that touch `date`, including ones crossing midnight into or out of it.
    func sessions(on date: LocalDate) -> [Session] {
        let day = date.interval(in: calendar)
        return allSessions.filter { session in
            session.start < day.end && (session.end ?? max(now, session.start)) > day.start
        }
    }

    func keepGap() {
        notice = nil
    }

    func stopAtGapStart() {
        guard case let .askedAboutGap(sessionID, from, _) = notice else { return }
        perform { store in
            guard var session = try store.session(id: sessionID) else { throw SessionError.notFound }
            if session.isOpen {
                try store.stop(at: from, now: Date())
            } else if let end = session.end, end > from, from > session.start {
                session.end = from
                try store.update(session, now: Date())
            }
            notice = nil
        }
    }

    func undoAutoStop() {
        guard case let .autoStopped(session, _, _) = notice else { return }
        perform { store in
            if try store.session(id: session.id) != nil {
                try store.reopen(id: session.id, now: Date())
            } else {
                // The stop discarded a zero-length session; recreate it from its original start.
                try store.start(at: session.start, now: Date())
            }
            notice = nil
        }
    }

    func dismissNotice() {
        notice = nil
    }

    func recordHeartbeatNow() {
        guard isWorking, let store else { return }
        let date = Date()
        try? store.recordHeartbeat(at: date)
        openSession?.heartbeat = date
    }

    // MARK: Internals

    private func perform(_ action: (SessionStore) throws -> Void) {
        guard let store else { return }
        do {
            try action(store)
            errorMessage = nil
        } catch {
            show(error)
        }
        reload()
    }

    private func mutate(_ action: (SessionStore) throws -> Void) throws {
        guard let store else { throw SessionError.notFound }
        defer { reload() }
        try action(store)
        errorMessage = nil
    }

    private func show(_ error: Error) {
        show(message: error.localizedDescription)
    }

    private func show(message: String) {
        errorMessage = message
        errorClearTask?.cancel()
        errorClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.errorMessage = nil
        }
    }

    /// Re-reads everything from the database. Called after every change and at midnight.
    private func reload() {
        now = Date()
        today = LocalDate(now, calendar: calendar)
        guard let store else { return }
        do {
            openSession = try store.openSession()
            latestSession = try store.latestSession()
            let settings = try store.workSettings()
            workSettings = settings
            generalSettings = try store.generalSettings()
            let firstLaunch = try store.firstLaunchDate() ?? now
            accountingStart = settings.accountingStart ?? LocalDate(firstLaunch, calendar: calendar)
            workingCalendar = WorkingCalendar(
                settings: settings,
                overrides: try store.dayOverrides(),
                accountingStart: accountingStart
            )
            openingBalance = TimeInterval(settings.openingBalanceMinutes * 60)
            allSessions = try store.allSessions()
        } catch {
            show(error)
        }
        if let workingCalendar {
            ledger = Ledger(sessions: allSessions, workingCalendar: workingCalendar, calendar: calendar, now: now)
        }
        recomputeOverview()
        updateActivityAssertion()
    }

    private func recomputeOverview() {
        guard let ledger else { return }
        overview = Overview(ledger: ledger, openingBalance: openingBalance, today: today)
    }

    private func tick() {
        now = Date()
        if LocalDate(now, calendar: calendar) != today {
            reload()
        } else {
            ledger = ledger?.updated(now: now)
            recomputeOverview()
        }
        checkLiveness()
        sampleActivity()
    }

    private func checkLiveness() {
        guard let store, let session = openSession else { return }
        let current = Date()
        switch policy.evaluate(lastAlive: session.lastAlive, now: current) {
        case .continueSilently:
            if current.timeIntervalSince(session.lastAlive) >= Self.heartbeatInterval {
                recordHeartbeatNow()
            }
        case let .ask(gapStart, gapEnd):
            // Several gaps in one session merge into one question reaching back to the first.
            if case let .askedAboutGap(id, earlier, _) = notice, id == session.id {
                notice = .askedAboutGap(sessionID: id, from: earlier, to: gapEnd)
            } else {
                notice = .askedAboutGap(sessionID: session.id, from: gapStart, to: gapEnd)
            }
            recordHeartbeatNow()
        case let .autoStop(stopAt):
            do {
                try store.stop(at: stopAt, now: current)
                notice = .autoStopped(session: session, stoppedAt: stopAt, awayUntil: current)
            } catch {
                show(error)
            }
            reload()
        }
    }

    private func startTimer() {
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordHeartbeatNow() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
    }

    private func updateActivityAssertion() {
        if isWorking, activity == nil {
            // Without this, App Nap can stretch the heartbeat timer far beyond its interval
            // and make an ordinary afternoon look like a liveness gap. The Mac may still sleep.
            activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Tracking working time"
            )
        } else if !isWorking, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }
}
