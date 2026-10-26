import Foundation
import Testing
@testable import OlekCore

@Suite struct SessionStoreTests {
    let store: SessionStore

    init() throws {
        store = try .inMemory(now: at("2026-10-26T08:00:00+02:00"))
    }

    @Test func startAndStopRecordsTimestamps() throws {
        let started = try store.start(at: at("2026-10-26T08:30:00+02:00"), now: at("2026-10-26T08:30:00+02:00"))
        #expect(try store.openSession() == started)

        let result = try store.stop(at: at("2026-10-26T10:45:00+02:00"), now: at("2026-10-26T10:45:00+02:00"))
        guard case .stopped(let session) = result else {
            Issue.record("expected stopped, got \(result)")
            return
        }
        #expect(session.start == at("2026-10-26T08:30:00+02:00"))
        #expect(session.end == at("2026-10-26T10:45:00+02:00"))
        #expect(try store.openSession() == nil)
    }

    @Test func secondStartWhileRunningIsRejected() throws {
        try store.start(at: at("2026-10-26T08:30:00+02:00"), now: at("2026-10-26T08:30:00+02:00"))
        #expect(throws: SessionError.alreadyRunning) {
            try store.start(at: at("2026-10-26T08:31:00+02:00"), now: at("2026-10-26T08:31:00+02:00"))
        }
    }

    @Test func stopWithoutRunningSessionIsRejected() {
        #expect(throws: SessionError.notRunning) {
            try store.stop(at: at("2026-10-26T08:30:00+02:00"), now: at("2026-10-26T08:30:00+02:00"))
        }
    }

    @Test func zeroLengthSessionIsDiscarded() throws {
        let now = at("2026-10-26T08:30:00+02:00")
        try store.start(at: now, now: now)
        let result = try store.stop(at: now.addingTimeInterval(0.4), now: now.addingTimeInterval(0.4))
        guard case .discarded = result else {
            Issue.record("expected discarded, got \(result)")
            return
        }
        #expect(try store.sessions(overlapping: DateInterval(start: now.addingTimeInterval(-3600), duration: 7200)).isEmpty)
    }

    @Test func multipleSessionsPerDayAreReturnedInOrder() throws {
        let pairs = [("08:30", "10:45"), ("11:00", "12:15"), ("13:00", "17:00")]
        for (start, end) in pairs {
            try store.start(at: at("2026-10-26T\(start):00+02:00"), now: at("2026-10-26T\(start):00+02:00"))
            try store.stop(at: at("2026-10-26T\(end):00+02:00"), now: at("2026-10-26T\(end):00+02:00"))
        }
        let day = calendar().dateInterval(of: .day, for: at("2026-10-26T12:00:00+02:00"))!
        let sessions = try store.sessions(overlapping: day)
        #expect(sessions.count == 3)
        #expect(sessions.map(\.start) == sessions.map(\.start).sorted())
    }

    @Test func startInsideAnExistingSessionIsRejected() throws {
        try store.start(at: at("2026-10-26T09:00:00+02:00"), now: at("2026-10-26T09:00:00+02:00"))
        try store.stop(at: at("2026-10-26T10:00:00+02:00"), now: at("2026-10-26T10:00:00+02:00"))

        // "Started 10 minutes ago" would reach back into the previous session.
        #expect(throws: SessionError.self) {
            try store.start(at: at("2026-10-26T09:55:00+02:00"), now: at("2026-10-26T10:02:00+02:00"))
        }
    }

    @Test func backToBackSessionsDoNotOverlap() throws {
        try store.start(at: at("2026-10-26T09:00:00+02:00"), now: at("2026-10-26T09:00:00+02:00"))
        try store.stop(at: at("2026-10-26T10:00:00+02:00"), now: at("2026-10-26T10:00:00+02:00"))
        try store.start(at: at("2026-10-26T10:00:00+02:00"), now: at("2026-10-26T10:00:00+02:00"))
        #expect(try store.openSession() != nil)
    }

    @Test func editingIntoAnotherSessionIsRejected() throws {
        try store.start(at: at("2026-10-26T09:00:00+02:00"), now: at("2026-10-26T09:00:00+02:00"))
        try store.stop(at: at("2026-10-26T10:00:00+02:00"), now: at("2026-10-26T10:00:00+02:00"))
        let second = try store.start(at: at("2026-10-26T11:00:00+02:00"), now: at("2026-10-26T11:00:00+02:00"))
        guard case .stopped(var edited) = try store.stop(at: at("2026-10-26T12:00:00+02:00"), now: at("2026-10-26T12:00:00+02:00")) else {
            Issue.record("expected stopped")
            return
        }
        #expect(edited.id == second.id)

        edited.start = at("2026-10-26T09:30:00+02:00")
        #expect(throws: SessionError.self) { try store.update(edited, now: at("2026-10-26T12:00:00+02:00")) }

        edited.start = at("2026-10-26T10:00:00+02:00")
        let saved = try store.update(edited, now: at("2026-10-26T12:00:00+02:00"))
        #expect(saved.start == at("2026-10-26T10:00:00+02:00"))
    }

    @Test func editingRejectsNegativeDurationAndFutureTimes() throws {
        try store.start(at: at("2026-10-26T09:00:00+02:00"), now: at("2026-10-26T09:00:00+02:00"))
        guard case .stopped(var session) = try store.stop(at: at("2026-10-26T10:00:00+02:00"), now: at("2026-10-26T10:00:00+02:00")) else {
            Issue.record("expected stopped")
            return
        }
        let now = at("2026-10-26T12:00:00+02:00")

        session.end = at("2026-10-26T08:00:00+02:00")
        #expect(throws: SessionError.endNotAfterStart) { try store.update(session, now: now) }

        session.end = at("2026-10-26T13:00:00+02:00")
        #expect(throws: SessionError.inFuture) { try store.update(session, now: now) }
    }

    @Test func openSessionBlocksAddingSessionsAfterItsStart() throws {
        try store.start(at: at("2026-10-26T09:00:00+02:00"), now: at("2026-10-26T09:00:00+02:00"))
        try store.stop(at: at("2026-10-26T09:30:00+02:00"), now: at("2026-10-26T09:30:00+02:00"))
        try store.start(at: at("2026-10-26T10:00:00+02:00"), now: at("2026-10-26T10:00:00+02:00"))

        // Moving the closed session into the running one's time span must fail.
        var closed = try #require(try store.sessions(overlapping: DateInterval(start: at("2026-10-26T08:00:00+02:00"), duration: 5400)).first)
        closed.end = at("2026-10-26T10:30:00+02:00")
        #expect(throws: SessionError.self) { try store.update(closed, now: at("2026-10-26T11:00:00+02:00")) }
    }

    @Test func reopenRestoresRunningState() throws {
        let session = try store.start(at: at("2026-10-26T09:00:00+02:00"), now: at("2026-10-26T09:00:00+02:00"))
        try store.stop(at: at("2026-10-26T09:40:00+02:00"), now: at("2026-10-26T15:00:00+02:00"))

        let reopened = try store.reopen(id: session.id, now: at("2026-10-26T15:00:00+02:00"))
        #expect(reopened.end == nil)
        #expect(reopened.heartbeat == at("2026-10-26T15:00:00+02:00"))
        #expect(try store.openSession()?.id == session.id)
    }

    @Test func reopenIsRefusedWhenALaterSessionExists() throws {
        let first = try store.start(at: at("2026-10-26T09:00:00+02:00"), now: at("2026-10-26T09:00:00+02:00"))
        try store.stop(at: at("2026-10-26T09:40:00+02:00"), now: at("2026-10-26T15:00:00+02:00"))
        try store.start(at: at("2026-10-26T15:00:00+02:00"), now: at("2026-10-26T15:00:00+02:00"))
        try store.stop(at: at("2026-10-26T15:30:00+02:00"), now: at("2026-10-26T15:30:00+02:00"))

        #expect(throws: SessionError.self) { try store.reopen(id: first.id, now: at("2026-10-26T16:00:00+02:00")) }
    }

    @Test func heartbeatOnlyTouchesTheOpenSession() throws {
        try store.start(at: at("2026-10-26T09:00:00+02:00"), now: at("2026-10-26T09:00:00+02:00"))
        try store.recordHeartbeat(at: at("2026-10-26T09:05:00+02:00"))
        #expect(try store.openSession()?.heartbeat == at("2026-10-26T09:05:00+02:00"))
        #expect(try store.openSession()?.lastAlive == at("2026-10-26T09:05:00+02:00"))
    }

    @Test func firstLaunchDateIsRecordedOnce() throws {
        #expect(try store.firstLaunchDate() == at("2026-10-26T08:00:00+02:00"))
    }
}

@Suite struct PersistenceTests {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("olek-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("olek.sqlite")
    }

    @Test func openSessionSurvivesReopeningTheDatabase() throws {
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let started: Session
        do {
            let store = try SessionStore(url: url, now: at("2026-10-26T08:00:00+02:00"))
            started = try store.start(at: at("2026-10-26T09:00:00+02:00"), now: at("2026-10-26T09:00:00+02:00"))
            try store.recordHeartbeat(at: at("2026-10-26T09:10:00+02:00"))
        }
        let reopened = try SessionStore(url: url, now: at("2026-10-27T08:00:00+02:00"))
        let session = try #require(try reopened.openSession())
        #expect(session.id == started.id)
        #expect(session.heartbeat == at("2026-10-26T09:10:00+02:00"))
        #expect(try reopened.firstLaunchDate() == at("2026-10-26T08:00:00+02:00"))
    }

    @Test func migrationSetsSchemaVersion() throws {
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = try SessionStore(url: url)
        let db = try Database(path: url.path)
        #expect(try db.userVersion() == Migrations.latestVersion)
    }

    @Test func newerSchemaIsRefused() throws {
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = try SessionStore(url: url)
        try Database(path: url.path).execute("PRAGMA user_version = \(Migrations.latestVersion + 1)")
        #expect(throws: DatabaseError.self) { try SessionStore(url: url) }
    }
}
