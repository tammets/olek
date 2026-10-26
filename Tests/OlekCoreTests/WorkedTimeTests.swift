import Foundation
import Testing
import OlekCore

@Suite struct WorkedTimeTests {
    func session(_ start: String, _ end: String?) -> Session {
        Session(id: 0, start: at(start), end: end.map(at))
    }

    @Test func sumsMultipleSessions() {
        let sessions = [
            session("2026-10-26T08:30:00+02:00", "2026-10-26T10:45:00+02:00"),
            session("2026-10-26T11:00:00+02:00", "2026-10-26T12:15:00+02:00"),
            session("2026-10-26T13:00:00+02:00", "2026-10-26T17:00:00+02:00"),
        ]
        let day = calendar().dateInterval(of: .day, for: at("2026-10-26T12:00:00+02:00"))!
        let worked = WorkedTime.seconds(of: sessions, in: day, now: at("2026-10-26T20:00:00+02:00"))
        let expected: TimeInterval = 8_100 + 4_500 + 14_400
        #expect(worked == expected)
    }

    @Test func openSessionCountsUntilNow() {
        let sessions = [session("2026-10-26T09:00:00+02:00", nil)]
        let day = calendar().dateInterval(of: .day, for: at("2026-10-26T12:00:00+02:00"))!
        #expect(WorkedTime.seconds(of: sessions, in: day, now: at("2026-10-26T11:30:00+02:00")) == 2.5 * 3600)
    }

    @Test func sessionAcrossMidnightIsSplitBetweenDays() {
        let sessions = [session("2026-10-26T22:00:00+02:00", "2026-10-27T02:00:00+02:00")]
        let cal = calendar()
        let monday = cal.dateInterval(of: .day, for: at("2026-10-26T12:00:00+02:00"))!
        let tuesday = cal.dateInterval(of: .day, for: at("2026-10-27T12:00:00+02:00"))!
        let now = at("2026-10-27T12:00:00+02:00")
        #expect(WorkedTime.seconds(of: sessions, in: monday, now: now) == 2 * 3600)
        #expect(WorkedTime.seconds(of: sessions, in: tuesday, now: now) == 2 * 3600)
    }

    @Test func springForwardDayHas23Hours() {
        // Europe/Tallinn moved from 03:00 EET to 04:00 EEST on 2026-03-29.
        let sessions = [session("2026-03-28T20:00:00+02:00", "2026-03-30T04:00:00+03:00")]
        let day = calendar().dateInterval(of: .day, for: at("2026-03-29T12:00:00+03:00"))!
        #expect(day.duration == 23 * 3600)
        #expect(WorkedTime.seconds(of: sessions, in: day, now: at("2026-04-01T00:00:00+03:00")) == 23 * 3600)
    }

    @Test func fallBackDayHas25Hours() {
        // Europe/Tallinn moved from 04:00 EEST back to 03:00 EET on 2026-10-25.
        let sessions = [session("2026-10-25T02:00:00+03:00", "2026-10-25T05:00:00+02:00")]
        let day = calendar().dateInterval(of: .day, for: at("2026-10-25T12:00:00+02:00"))!
        #expect(day.duration == 25 * 3600)
        // 02:00 to 05:00 local on that night spans four real hours.
        #expect(WorkedTime.seconds(of: sessions, in: day, now: at("2026-10-26T00:00:00+02:00")) == 4 * 3600)
    }

    @Test func timeZoneChangeKeepsTotalsAcrossDays() {
        let sessions = [session("2026-10-26T22:00:00+02:00", "2026-10-27T02:00:00+02:00")]
        let cal = calendar(in: TimeZone(identifier: "Europe/London")!)
        let now = at("2026-10-28T00:00:00+02:00")
        let first = cal.dateInterval(of: .day, for: at("2026-10-26T12:00:00+00:00"))!
        let second = cal.dateInterval(of: .day, for: at("2026-10-27T12:00:00+00:00"))!
        let a = WorkedTime.seconds(of: sessions, in: first, now: now)
        let b = WorkedTime.seconds(of: sessions, in: second, now: now)
        #expect(a == 4 * 3600)
        #expect(b == 0)
        #expect(a + b == 4 * 3600)
    }
}

@Suite struct FormattingTests {
    @Test func hoursAndMinutes() {
        #expect(DurationFormat.hoursMinutes(0) == "0m")
        #expect(DurationFormat.hoursMinutes(59) == "0m")
        #expect(DurationFormat.hoursMinutes(45 * 60) == "45m")
        #expect(DurationFormat.hoursMinutes(6.5 * 3600) == "6h 30m")
        #expect(DurationFormat.hoursMinutes(8 * 3600) == "8h")
        #expect(DurationFormat.hoursMinutes(-1.5 * 3600) == "\u{2212}1h 30m")
        #expect(DurationFormat.hoursMinutes(-30) == "0m")
    }

    @Test func signedDurations() {
        #expect(DurationFormat.signed(2.25 * 3600) == "+2h 15m")
        #expect(DurationFormat.signed(-1.5 * 3600) == "\u{2212}1h 30m")
        #expect(DurationFormat.signed(20) == "0m")
    }

    @Test func percentRoundsDown() {
        #expect(PercentFormat.whole(0.8125) == "81%")
        #expect(PercentFormat.whole(0.9999) == "99%")
        #expect(PercentFormat.whole(1.05) == "105%")
    }

    @Test func clock() {
        #expect(DurationFormat.clock(0) == "0:00:00")
        #expect(DurationFormat.clock(2 * 3600 + 14 * 60 + 7) == "2:14:07")
    }

    @Test func timeIsAlways24Hour() {
        #expect(TimeFormat.hourMinute(at("2026-10-26T17:03:00+02:00"), timeZone: tallinn) == "17:03")
        #expect(TimeFormat.hourMinute(at("2026-10-26T09:12:00+02:00"), timeZone: tallinn) == "09:12")
    }
}
