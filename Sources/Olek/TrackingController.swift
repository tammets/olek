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
    private(set) var errorMessage: String?

    var isWorking: Bool { openSession != nil }

    /// The session the quick-adjust buttons act on: the running one, else the most recent.
    var adjustableSession: Session? { openSession ?? latestSession }

    @ObservationIgnored private let store: SessionStore?
    @ObservationIgnored private let policy = RecoveryPolicy()
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
        reload()
        checkLiveness()
        startTimer()
        observeSystem()
    }

    func sessionDuration(at date: Date) -> TimeInterval? {
        openSession.map { date.timeIntervalSince($0.start) }
    }

    // MARK: Actions

    func toggle() {
        isWorking ? stop() : start()
    }

    func start() {
        perform {
            try $0.start(at: Date(), now: Date())
            if case .autoStopped = notice { notice = nil }
        }
    }

    func stop() {
        perform { try $0.stop(at: Date(), now: Date()) }
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
        errorMessage = error.localizedDescription
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
            let firstLaunch = try store.firstLaunchDate() ?? now
            let accountingStart = settings.accountingStart ?? LocalDate(firstLaunch, calendar: calendar)
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
