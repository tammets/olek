import Foundation
import Testing
import OlekCore

@Suite struct RecoveryPolicyTests {
    let policy = RecoveryPolicy()
    let lastAlive = at("2026-10-26T12:00:00+02:00")

    @Test func shortGapIsIgnored() {
        #expect(policy.evaluate(lastAlive: lastAlive, now: at("2026-10-26T12:14:59+02:00")) == .continueSilently)
    }

    @Test func mediumGapAsks() {
        let now = at("2026-10-26T12:15:00+02:00")
        #expect(policy.evaluate(lastAlive: lastAlive, now: now) == .ask(gapStart: lastAlive, gapEnd: now))
        let later = at("2026-10-26T15:59:59+02:00")
        #expect(policy.evaluate(lastAlive: lastAlive, now: later) == .ask(gapStart: lastAlive, gapEnd: later))
    }

    @Test func longGapStopsAtLastAliveMoment() {
        #expect(policy.evaluate(lastAlive: lastAlive, now: at("2026-10-26T16:00:00+02:00")) == .autoStop(at: lastAlive))
        #expect(policy.evaluate(lastAlive: lastAlive, now: at("2026-10-29T08:00:00+02:00")) == .autoStop(at: lastAlive))
    }

    @Test func clockMovingBackwardsIsIgnored() {
        #expect(policy.evaluate(lastAlive: lastAlive, now: at("2026-10-26T11:00:00+02:00")) == .continueSilently)
    }

    @Test func autoStopNeverFabricatesTime() throws {
        // Laptop closed Friday evening while tracking, opened Monday morning.
        let store = try SessionStore.inMemory()
        try store.start(at: at("2026-10-23T09:00:00+03:00"), now: at("2026-10-23T09:00:00+03:00"))
        try store.recordHeartbeat(at: at("2026-10-23T17:30:00+03:00"))

        let now = at("2026-10-26T08:45:00+02:00")
        let session = try #require(try store.openSession())
        guard case .autoStop(let stopAt) = policy.evaluate(lastAlive: session.lastAlive, now: now) else {
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
