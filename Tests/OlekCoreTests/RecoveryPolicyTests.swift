import Foundation
import Testing
import OlekCore

@Suite struct RecoveryPolicyTests {
    let policy = RecoveryPolicy()
    let lastSeen = at("2026-10-26T12:00:00+02:00")

    @Test func shortAbsenceIsIgnored() {
        let back = at("2026-10-26T12:14:59+02:00")
        #expect(policy.evaluate(lastSeen: lastSeen, presence: back, now: back) == .record(presence: back))
    }

    @Test func mediumAbsenceAsksWithTheReturnTime() {
        let back = at("2026-10-26T12:15:00+02:00")
        let now = at("2026-10-26T12:15:08+02:00")
        #expect(policy.evaluate(lastSeen: lastSeen, presence: back, now: now) == .ask(gapStart: lastSeen, gapEnd: back))
        let later = at("2026-10-26T15:59:59+02:00")
        #expect(policy.evaluate(lastSeen: lastSeen, presence: later, now: later) == .ask(gapStart: lastSeen, gapEnd: later))
    }

    @Test func longAbsenceStopsWhenThePersonLeft() {
        let back = at("2026-10-26T16:00:00+02:00")
        #expect(policy.evaluate(lastSeen: lastSeen, presence: back, now: back) == .autoStop(at: lastSeen))
        let monday = at("2026-10-29T08:00:00+02:00")
        #expect(policy.evaluate(lastSeen: lastSeen, presence: monday, now: monday) == .autoStop(at: lastSeen))
    }

    @Test func stillAwayWithTheScreenOnStopsAfterTheLimit() {
        // No input since the last sighting: the idle time keeps pointing at it.
        #expect(policy.evaluate(lastSeen: lastSeen, presence: lastSeen, now: at("2026-10-26T15:59:00+02:00")) == .nothing)
        #expect(policy.evaluate(lastSeen: lastSeen, presence: lastSeen, now: at("2026-10-26T16:00:00+02:00")) == .autoStop(at: lastSeen))
    }

    @Test func darkScreensNeverCountAsPresence() {
        // Lid closed at 12:00; macOS keeps waking briefly in the background with the screens off.
        #expect(policy.evaluate(lastSeen: lastSeen, presence: nil, now: at("2026-10-26T12:20:00+02:00")) == .nothing)
        #expect(policy.evaluate(lastSeen: lastSeen, presence: nil, now: at("2026-10-26T16:05:00+02:00")) == .autoStop(at: lastSeen))
    }

    @Test func overnightWithBackgroundWakesStopsAtTheLastSighting() {
        // The situation that kept a session running for 25 hours: closed at 15:58, dozens of
        // maintenance wakes overnight, opened again at 07:52.
        let closed = at("2026-10-30T15:58:00+02:00")
        var time = closed
        while time < at("2026-10-31T07:52:00+02:00") {
            time += 15 * 60
            if case .autoStop(let stopAt) = policy.evaluate(lastSeen: closed, presence: nil, now: time) {
                #expect(stopAt == closed)
                return
            }
        }
        Issue.record("expected an automatic stop during the night")
    }

    @Test func presenceIsRecordedOncePerMinuteOrWhenInputPauses() {
        let typing = at("2026-10-26T12:00:30+02:00")
        #expect(policy.evaluate(lastSeen: lastSeen, presence: typing, now: typing) == .nothing)
        let minuteLater = at("2026-10-26T12:01:00+02:00")
        #expect(policy.evaluate(lastSeen: lastSeen, presence: minuteLater, now: minuteLater) == .record(presence: minuteLater))
        // Input stopped at 12:00:30 and a minute has passed: store exactly when it stopped.
        #expect(policy.evaluate(lastSeen: lastSeen, presence: typing, now: at("2026-10-26T12:01:30+02:00")) == .record(presence: typing))
        // Within the same stored second it is the same sighting.
        #expect(policy.evaluate(lastSeen: lastSeen, presence: lastSeen + 0.7, now: at("2026-10-26T12:05:00+02:00")) == .nothing)
    }

    @Test func clockMovingBackwardsIsIgnored() {
        let earlier = at("2026-10-26T11:00:00+02:00")
        #expect(policy.evaluate(lastSeen: lastSeen, presence: earlier, now: earlier) == .nothing)
    }

    @Test func autoStopNeverFabricatesTime() throws {
        // Laptop closed Friday evening while tracking, opened Monday morning.
        let store = try SessionStore.inMemory()
        try store.start(at: at("2026-10-23T09:00:00+03:00"), now: at("2026-10-23T09:00:00+03:00"))
        try store.recordHeartbeat(at: at("2026-10-23T17:30:00+03:00"))

        let now = at("2026-10-26T08:45:00+02:00")
        let session = try #require(try store.openSession())
        guard case .autoStop(let stopAt) = policy.evaluate(lastSeen: session.lastAlive, presence: now, now: now) else {
            Issue.record("expected autoStop")
            return
        }
        guard case .stopped(let stopped) = try store.stop(at: stopAt, now: now) else {
            Issue.record("expected stopped")
            return
        }
        #expect(stopped.end == at("2026-10-23T17:30:00+03:00"))
    }
}
