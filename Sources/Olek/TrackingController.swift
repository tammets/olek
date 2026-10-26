import AppKit
import Observation
import OlekCore

enum RecoveryNotice: Equatable {
    /// The Mac slept or Olek was not running for a while; the session kept going.
    case askedAboutGap(sessionID: Int64, from: Date, to: Date)
    /// The gap was long enough that the session was stopped at its start.
    case autoStopped(session: Session, stoppedAt: Date, awayUntil: Date)
}

@MainActor
@Observable
final class TrackingController {
    private(set) var openSession: Session?
    private(set) var now = Date()
    private(set) var notice: RecoveryNotice?
    private(set) var errorMessage: String?

    var isWorking: Bool { openSession != nil }

    @ObservationIgnored private let store: SessionStore?
    @ObservationIgnored private let policy = RecoveryPolicy()
    @ObservationIgnored private let calendar = Calendar.autoupdatingCurrent
    @ObservationIgnored private var today: DateInterval
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var activity: NSObjectProtocol?
    private var todaySessions: [Session] = []

    private static let tickInterval: TimeInterval = 10
    private static let heartbeatInterval: TimeInterval = 60

    init() {
        today = Calendar.autoupdatingCurrent.dateInterval(of: .day, for: Date())!
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

    // MARK: Derived values

    func todayWorked(at date: Date) -> TimeInterval {
        WorkedTime.seconds(of: todaySessions, in: today, now: date)
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

    func keepGap() {
        notice = nil
    }

    func stopAtGapStart() {
        guard case let .askedAboutGap(sessionID, from, _) = notice else { return }
        perform { store in
            guard var session = try store.session(id: sessionID) else { throw SessionError.notFound }
            if session.isOpen {
                try store.stop(at: from, now: Date())
            } else if let end = session.end, end > from {
                session.end = from
                if from > session.start {
                    try store.update(session, now: Date())
                }
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
            errorMessage = error.localizedDescription
        }
        reload()
    }

    private func reload() {
        now = Date()
        today = calendar.dateInterval(of: .day, for: now)!
        guard let store else { return }
        do {
            openSession = try store.openSession()
            todaySessions = try store.sessions(overlapping: today)
        } catch {
            errorMessage = error.localizedDescription
        }
        updateActivityAssertion()
    }

    private func tick() {
        now = Date()
        if now < today.start || now >= today.end {
            reload()
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
                errorMessage = error.localizedDescription
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
