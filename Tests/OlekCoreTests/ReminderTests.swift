import Foundation
import Testing
import OlekCore

@Suite struct ReminderEngineTests {
    let start = at("2026-10-26T09:00:00+02:00")

    /// Feeds samples every 10 seconds for `minutes`, with `idle(t)` giving seconds since input.
    func run(
        _ engine: inout ReminderEngine,
        from offset: TimeInterval = 0,
        minutes: Double,
        tracking: Bool,
        workExpected: Bool = true,
        idle: (TimeInterval) -> TimeInterval
    ) -> [(TimeInterval, Reminder)] {
        var fired: [(TimeInterval, Reminder)] = []
        var t = offset
        while t < offset + minutes * 60 {
            if let r = engine.sample(now: start.addingTimeInterval(t), idleSeconds: idle(t), isTracking: tracking, workExpected: workExpected) {
                fired.append((t, r))
            }
            t += 10
        }
        return fired
    }

    @Test func activeWhileStoppedFiresAfterTenMinutesOfUse() {
        var engine = ReminderEngine(settings: ReminderSettings())
        let fired = run(&engine, minutes: 30, tracking: false) { _ in 3 }
        #expect(fired.count == 1)
        // Input was seen 3 seconds before the first sample, so ten minutes are complete at t = 600.
        let expectedTime: TimeInterval = 600
        #expect(fired.first?.0 == expectedTime)
        #expect(fired.first?.1 == .activeWhileStopped(activeSince: start.addingTimeInterval(-3)))
    }

    @Test func activeReminderNeedsAScheduledUnfinishedDay() {
        var engine = ReminderEngine(settings: ReminderSettings())
        #expect(run(&engine, minutes: 30, tracking: false, workExpected: false) { _ in 3 }.isEmpty)
    }

    @Test func shortBreaksKeepTheStreakButLongOnesResetIt() {
        var engine = ReminderEngine(settings: ReminderSettings())
        // Reading for 100 seconds at a time never breaks the streak.
        let continuous = run(&engine, minutes: 11, tracking: false) { t in t.truncatingRemainder(dividingBy: 100) }
        #expect(continuous.count == 1)

        var other = ReminderEngine(settings: ReminderSettings())
        // Five minutes of use, three minutes away, five minutes of use: no ten-minute streak.
        let broken = run(&other, minutes: 13, tracking: false) { t in
            (300..<480).contains(t) ? t - 300 : 2
        }
        #expect(broken.isEmpty)
    }

    @Test func idleWhileTrackingFiresOnceWithTheStartOfInactivity() {
        var engine = ReminderEngine(settings: ReminderSettings())
        // Last input at t = 60, then nothing for 40 minutes.
        let fired = run(&engine, minutes: 40, tracking: true) { t in t < 60 ? 0 : t - 60 }
        #expect(fired.count == 1)
        #expect(fired.first?.1 == .idleWhileTracking(idleSince: start.addingTimeInterval(60)))
        let expectedTime: TimeInterval = 960
        #expect(fired.first?.0 == expectedTime)
    }

    @Test func idleReminderRearmsOnlyAfterActivityAndSpacing() {
        var engine = ReminderEngine(settings: ReminderSettings())
        // Away 09:01-09:20, back 09:20-09:25, away again from 09:25.
        let idle: (TimeInterval) -> TimeInterval = { t in
            switch t {
            case ..<60: 0
            case ..<1200: t - 60
            case ..<1500: 0
            default: t - 1500
            }
        }
        let fired = run(&engine, minutes: 90, tracking: true, idle: idle)
        // First at 09:16; the second idle period passes 15 minutes at 09:40, but spacing
        // holds it until 30 minutes after the first reminder, 09:46.
        #expect(fired.map(\.0) == [960, 2760])
    }

    @Test func snoozeRepeatsTheSameReminder() {
        var engine = ReminderEngine(settings: ReminderSettings())
        let first = run(&engine, minutes: 16, tracking: true) { t in t }
        #expect(first.count == 1)
        engine.snooze(.idle, now: start.addingTimeInterval(first[0].0))
        let later = run(&engine, from: 16 * 60, minutes: 20, tracking: true) { t in t }
        #expect(later.count == 1)
        #expect(later.first?.0 == first[0].0 + 15 * 60)
    }

    @Test func notWorkingWaitsForTheNextAbsence() {
        var engine = ReminderEngine(settings: ReminderSettings())
        let first = run(&engine, minutes: 11, tracking: false) { _ in 1 }
        #expect(first.count == 1)
        engine.dismissActive()
        #expect(run(&engine, from: 11 * 60, minutes: 60, tracking: false) { _ in 1 }.isEmpty)

        // Away for 20 minutes, then back for 11.
        let afterAbsence = run(&engine, from: 71 * 60, minutes: 32, tracking: false) { t in
            t < 91 * 60 ? t - 71 * 60 : 1
        }
        #expect(afterAbsence.count == 1)
    }

    @Test func stoppingTrackingDoesNotTriggerAnImmediateReminder() {
        var engine = ReminderEngine(settings: ReminderSettings())
        _ = run(&engine, minutes: 60, tracking: true) { _ in 1 }
        engine.trackingStopped()
        #expect(run(&engine, from: 3600, minutes: 30, tracking: false) { _ in 1 }.isEmpty)
    }

    @Test func sleepGapBreaksTheStreakAndRearms() {
        var engine = ReminderEngine(settings: ReminderSettings())
        engine.trackingStopped()
        _ = run(&engine, minutes: 8, tracking: false) { _ in 1 }
        // Lid closed for an hour; on wake the clock jumps and input is fresh.
        let afterWake = run(&engine, from: 68 * 60, minutes: 11, tracking: false) { _ in 1 }
        #expect(afterWake.count == 1)
        #expect(afterWake.first?.1 == .activeWhileStopped(activeSince: start.addingTimeInterval(68 * 60 - 1)))
    }

    @Test func disabledRemindersStayQuiet() {
        var settings = ReminderSettings()
        settings.idleReminderEnabled = false
        settings.activeReminderEnabled = false
        var engine = ReminderEngine(settings: settings)
        #expect(run(&engine, minutes: 30, tracking: true) { t in t }.isEmpty)
        #expect(run(&engine, from: 1800, minutes: 30, tracking: false) { _ in 1 }.isEmpty)
    }

    @Test func settingsDriveRecoveryPolicy() {
        var settings = ReminderSettings()
        settings.idleThresholdMinutes = 20
        settings.autoStopHours = 6
        #expect(settings.recoveryPolicy.askThreshold == 1200)
        #expect(settings.recoveryPolicy.autoStopThreshold == 6 * 3600)
    }

    @Test func settingsPersist() throws {
        let store = try SessionStore.inMemory()
        #expect(try store.reminderSettings() == ReminderSettings())
        var settings = ReminderSettings()
        settings.snoozeMinutes = 25
        try store.saveReminderSettings(settings)
        #expect(try store.reminderSettings() == settings)
    }
}

@Suite struct TimeParseTests {
    let reference = at("2026-10-26T14:00:00+02:00")

    @Test(arguments: ["9:15", "09:15", "9.15", "915", "0915"])
    func acceptedForms(_ text: String) {
        #expect(TimeParse.time(text, sameDayAs: reference, calendar: calendar()) == at("2026-10-26T09:15:00+02:00"))
    }

    @Test func hourOnly() {
        #expect(TimeParse.time("9", sameDayAs: reference, calendar: calendar()) == at("2026-10-26T09:00:00+02:00"))
    }

    @Test(arguments: ["", "25:00", "9:60", "9:5", "abc", "12345", "9:15:00"])
    func rejected(_ text: String) {
        #expect(TimeParse.time(text, sameDayAs: reference, calendar: calendar()) == nil)
    }
}
