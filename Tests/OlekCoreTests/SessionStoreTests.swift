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

@Suite struct SettingsStoreTests {
    let store: SessionStore

    init() throws {
        store = try .inMemory(now: at("2026-10-26T08:00:00+02:00"))
    }

    @Test func defaultsWhenNothingSaved() throws {
        #expect(try store.workSettings() == WorkSettings())
    }

    @Test func settingsRoundTrip() throws {
        var settings = WorkSettings()
        settings.accountingStart = day("2026-01-01")
        settings.openingBalanceMinutes = -150
        settings.minutesByWeekday = [450, 450, 450, 450, 360, 0, 0]
        try store.saveWorkSettings(settings)
        #expect(try store.workSettings() == settings)
    }

    @Test func overridesUpsertAndRemove() throws {
        let now = at("2026-10-26T08:00:00+02:00")
        try store.setDayOverride(DayOverride(date: day("2026-10-27"), kind: .vacation), now: now)
        try store.setDayOverride(DayOverride(date: day("2026-10-27"), kind: .minutes, expectedMinutes: 240, note: "Dentist"), now: now)
        #expect(try store.dayOverrides() == [DayOverride(date: day("2026-10-27"), kind: .minutes, expectedMinutes: 240, note: "Dentist")])

        try store.removeDayOverride(on: day("2026-10-27"))
        #expect(try store.dayOverrides().isEmpty)
    }

    @Test func overrideMinutesAreValidated() {
        #expect(throws: SessionError.invalidExpectedMinutes) {
            try store.setDayOverride(DayOverride(date: day("2026-10-27"), kind: .customWorking), now: at("2026-10-26T08:00:00+02:00"))
        }
    }

    @Test func latestSessionIsTheMostRecentStart() throws {
        try store.start(at: at("2026-10-26T09:00:00+02:00"), now: at("2026-10-26T09:00:00+02:00"))
        try store.stop(at: at("2026-10-26T10:00:00+02:00"), now: at("2026-10-26T10:00:00+02:00"))
        let second = try store.start(at: at("2026-10-26T11:00:00+02:00"), now: at("2026-10-26T11:00:00+02:00"))
        #expect(try store.latestSession()?.id == second.id)
    }
}

@Suite struct HistoryEditingTests {
    let store: SessionStore

    init() throws {
        store = try .inMemory(now: at("2026-10-20T08:00:00+03:00"))
    }

    @Test func addForgottenSession() throws {
        let added = try store.add(
            start: at("2026-10-23T09:00:00+03:00"),
            end: at("2026-10-23T17:00:00+03:00"),
            note: "Forgot to start",
            now: at("2026-10-26T10:00:00+02:00")
        )
        #expect(added.note == "Forgot to start")
        #expect(try store.allSessions() == [added])
    }

    @Test func addRejectsOverlapAndFuture() throws {
        let now = at("2026-10-26T10:00:00+02:00")
        try store.add(start: at("2026-10-23T09:00:00+03:00"), end: at("2026-10-23T17:00:00+03:00"), now: now)
        #expect(throws: SessionError.overlaps(with: 1)) {
            try store.add(start: at("2026-10-23T16:00:00+03:00"), end: at("2026-10-23T18:00:00+03:00"), now: now)
        }
        #expect(throws: SessionError.inFuture) {
            try store.add(start: at("2026-10-26T09:00:00+02:00"), end: at("2026-10-26T11:00:00+02:00"), now: now)
        }
    }

    @Test func deleteRemovesOnlyThatSession() throws {
        let now = at("2026-10-26T10:00:00+02:00")
        let first = try store.add(start: at("2026-10-23T09:00:00+03:00"), end: at("2026-10-23T12:00:00+03:00"), now: now)
        let second = try store.add(start: at("2026-10-23T13:00:00+03:00"), end: at("2026-10-23T17:00:00+03:00"), now: now)
        try store.delete(id: first.id)
        #expect(try store.allSessions() == [second])
        #expect(throws: SessionError.notFound) { try store.delete(id: first.id) }
    }

    @Test func breakSplitsAClosedSession() throws {
        let now = at("2026-10-26T10:00:00+02:00")
        let session = try store.add(start: at("2026-10-23T09:00:00+03:00"), end: at("2026-10-23T17:00:00+03:00"), note: "Client", now: now)
        let (before, after) = try store.insertBreak(
            sessionID: session.id,
            from: at("2026-10-23T12:00:00+03:00"),
            to: at("2026-10-23T12:45:00+03:00"),
            now: now
        )
        #expect(before.end == at("2026-10-23T12:00:00+03:00"))
        #expect(after.start == at("2026-10-23T12:45:00+03:00"))
        #expect(after.end == at("2026-10-23T17:00:00+03:00"))
        #expect(after.note == "Client")
    }

    @Test func breakInRunningSessionKeepsSecondPartRunning() throws {
        try store.start(at: at("2026-10-26T08:00:00+02:00"), now: at("2026-10-26T08:00:00+02:00"))
        let open = try #require(try store.openSession())
        let (before, after) = try store.insertBreak(
            sessionID: open.id,
            from: at("2026-10-26T12:00:00+02:00"),
            to: at("2026-10-26T12:30:00+02:00"),
            now: at("2026-10-26T15:00:00+02:00")
        )
        #expect(before.end == at("2026-10-26T12:00:00+02:00"))
        #expect(after.isOpen)
        #expect(try store.openSession()?.id == after.id)
    }

    @Test func breakMustFitInsideTheSession() throws {
        let now = at("2026-10-26T10:00:00+02:00")
        let session = try store.add(start: at("2026-10-23T09:00:00+03:00"), end: at("2026-10-23T17:00:00+03:00"), now: now)
        #expect(throws: SessionError.breakOutsideSession) {
            try store.insertBreak(sessionID: session.id, from: at("2026-10-23T08:00:00+03:00"), to: at("2026-10-23T10:00:00+03:00"), now: now)
        }
        #expect(throws: SessionError.breakOutsideSession) {
            try store.insertBreak(sessionID: session.id, from: at("2026-10-23T12:00:00+03:00"), to: at("2026-10-23T11:00:00+03:00"), now: now)
        }
        #expect(throws: SessionError.breakOutsideSession) {
            try store.insertBreak(sessionID: session.id, from: at("2026-10-23T16:00:00+03:00"), to: at("2026-10-23T17:00:00+03:00"), now: now)
        }
    }

    @Test func removingAwayTimeKeepsTheRunningSessionGoing() throws {
        let open = try store.start(at: at("2026-10-26T08:00:00+02:00"), now: at("2026-10-26T08:00:00+02:00"))
        let now = at("2026-10-26T15:00:00+02:00")
        // Latest first, so the original session still holds the earlier span.
        try store.removeSpan(DateInterval(start: at("2026-10-26T12:00:00+02:00"), end: at("2026-10-26T12:45:00+02:00")), fromSession: open.id, now: now)
        try store.removeSpan(DateInterval(start: at("2026-10-26T10:00:00+02:00"), end: at("2026-10-26T10:30:00+02:00")), fromSession: open.id, now: now)
        let sessions = try store.allSessions()
        #expect(sessions.map(\.start) == [
            at("2026-10-26T08:00:00+02:00"), at("2026-10-26T10:30:00+02:00"), at("2026-10-26T12:45:00+02:00"),
        ])
        #expect(sessions.map(\.end) == [at("2026-10-26T10:00:00+02:00"), at("2026-10-26T12:00:00+02:00"), nil])
    }

    @Test func removingAwayTimeTrimsEdgesAndTouchesOnlyItsSession() throws {
        let now = at("2026-10-26T20:00:00+02:00")
        let morning = try store.add(start: at("2026-10-26T09:00:00+02:00"), end: at("2026-10-26T12:00:00+02:00"), now: now)
        let afternoon = try store.add(start: at("2026-10-26T14:00:00+02:00"), end: at("2026-10-26T17:00:00+02:00"), now: now)
        try store.removeSpan(DateInterval(start: at("2026-10-26T11:30:00+02:00"), end: at("2026-10-26T14:30:00+02:00")), fromSession: morning.id, now: now)
        #expect(try store.session(id: morning.id)?.end == at("2026-10-26T11:30:00+02:00"))
        #expect(try store.session(id: afternoon.id) == afternoon)
        try store.removeSpan(DateInterval(start: at("2026-10-26T13:00:00+02:00"), end: at("2026-10-26T14:30:00+02:00")), fromSession: afternoon.id, now: now)
        #expect(try store.session(id: afternoon.id)?.start == at("2026-10-26T14:30:00+02:00"))
    }

    @Test func removingAwayTimeFromADeletedSessionLeavesOthersAlone() throws {
        let now = at("2026-10-26T20:00:00+02:00")
        let manual = try store.add(start: at("2026-10-26T09:00:00+02:00"), end: at("2026-10-26T12:00:00+02:00"), now: now)
        let original = try store.add(start: at("2026-10-26T13:00:00+02:00"), end: at("2026-10-26T15:00:00+02:00"), now: now)
        try store.delete(id: original.id)
        try store.removeSpan(DateInterval(start: at("2026-10-26T10:00:00+02:00"), end: at("2026-10-26T10:30:00+02:00")), fromSession: original.id, now: now)
        #expect(try store.allSessions() == [manual])
    }

    @Test func stopRunningSessionAtAChosenPastTime() throws {
        try store.start(at: at("2026-10-26T08:00:00+02:00"), now: at("2026-10-26T08:00:00+02:00"))
        var session = try #require(try store.openSession())
        session.end = at("2026-10-26T16:30:00+02:00")
        let saved = try store.update(session, now: at("2026-10-26T19:00:00+02:00"))
        #expect(saved.end == at("2026-10-26T16:30:00+02:00"))
        #expect(try store.openSession() == nil)
    }
}
