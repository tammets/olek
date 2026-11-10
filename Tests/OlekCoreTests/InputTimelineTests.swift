import Foundation
import Testing
import OlekCore

@Suite struct InputTimelineTests {
    /// Drives a timeline the way the Mac's clocks move: uptime stands still during sleep.
    struct Mac {
        var timeline = InputTimeline()
        var now: Date
        var uptime: TimeInterval = 5_000
        var slept: TimeInterval = 0
        var inputUptime: TimeInterval

        init(lastInputAt start: Date) {
            now = start
            inputUptime = uptime
        }

        mutating func stayAwake(_ seconds: TimeInterval) {
            now += seconds
            uptime += seconds
        }

        mutating func sleep(_ seconds: TimeInterval) {
            now += seconds
            slept += seconds
        }

        mutating func touch() {
            inputUptime = uptime
        }

        mutating func sample() -> Date {
            timeline.sample(now: now, uptime: uptime, sleptTotal: slept, idleSeconds: uptime - inputUptime)
        }
    }

    @Test func awakeTheWholeTimeTheIdleTimeIsTakenAtFaceValue() {
        let start = at("2026-11-09T15:00:00+02:00")
        var mac = Mac(lastInputAt: start)
        #expect(mac.sample() == start)
        mac.stayAwake(600)
        #expect(mac.sample() == start)
        mac.touch()
        mac.stayAwake(5)
        #expect(mac.sample() == start + 600)
        #expect(mac.timeline.inputSinceWake)
    }

    @Test func backgroundWakesDoNotMoveTheLastInput() {
        // The night that produced sessions out of nothing: lid closed in the afternoon, then
        // a few seconds awake every quarter of an hour until the next morning.
        let left = at("2026-11-09T15:54:00+02:00")
        var mac = Mac(lastInputAt: left)
        mac.stayAwake(50)
        #expect(mac.sample() == left)
        while mac.now < at("2026-11-10T11:00:00+02:00") {
            mac.sleep(900)
            mac.stayAwake(3)
            #expect(mac.sample() == left)
            #expect(!mac.timeline.inputSinceWake)
            mac.stayAwake(4)
            #expect(mac.sample() == left)
        }
    }

    @Test func inputAfterWakingIsDatedFromTheWake() {
        let left = at("2026-11-09T15:54:00+02:00")
        var mac = Mac(lastInputAt: left)
        #expect(mac.sample() == left)
        mac.sleep(19 * 3600)
        mac.stayAwake(2)
        #expect(mac.sample() == left)
        mac.stayAwake(8)
        mac.touch()
        let back = mac.now
        mac.stayAwake(3)
        #expect(mac.sample() == back)
        #expect(mac.timeline.inputSinceWake)
        // Sitting idle afterwards keeps pointing at that input.
        mac.stayAwake(1200)
        #expect(mac.sample() == back)
    }

    @Test func theInputThatWakesTheMacCounts() {
        let left = at("2026-11-09T12:00:00+02:00")
        var mac = Mac(lastInputAt: left)
        #expect(mac.sample() == left)
        mac.sleep(3600)
        // A key press wakes the Mac and registers a moment into the wake; the first sample
        // comes two seconds later.
        mac.stayAwake(0.25)
        mac.touch()
        let back = mac.now
        mac.stayAwake(2)
        #expect(mac.sample() == back)
        #expect(mac.timeline.inputSinceWake)
    }

    @Test func inputBeforeTheSampleAtSleepStaysBeforeTheSleep() {
        let start = at("2026-11-09T15:00:00+02:00")
        var mac = Mac(lastInputAt: start)
        #expect(mac.sample() == start)
        // One more keystroke after the regular sample; the app samples again as the lid closes.
        mac.stayAwake(4)
        mac.touch()
        let seen = mac.now
        mac.stayAwake(1)
        #expect(mac.sample() == seen)
        for _ in 0..<3 {
            mac.sleep(900)
            mac.stayAwake(5)
            #expect(mac.sample() == seen)
            #expect(!mac.timeline.inputSinceWake)
        }
    }

    @Test func aClockSetBackMovesTheInputOnlyOnce() {
        let start = at("2026-11-09T15:00:00+02:00")
        var mac = Mac(lastInputAt: start)
        #expect(mac.sample() == start)
        mac.sleep(600)
        mac.now = start - 3600
        let corrected = mac.now
        #expect(mac.sample() == corrected)
        // Later background wakes do not keep reporting the person as just seen.
        mac.sleep(900)
        mac.stayAwake(5)
        #expect(mac.sample() == corrected)
        #expect(!mac.timeline.inputSinceWake)
    }
}
