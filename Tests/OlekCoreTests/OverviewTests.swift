import Foundation
import Testing
import OlekCore

@Suite struct OverviewTests {
    let cal = calendar()

    func session(_ start: String, _ end: String?) -> Session {
        Session(id: 0, start: at(start), end: end.map(at))
    }

    func overview(
        _ sessions: [Session],
        now: String,
        accountingStart: String,
        openingMinutes: Int = 0,
        overrides: [DayOverride] = []
    ) -> Overview {
        let working = WorkingCalendar(settings: WorkSettings(), overrides: overrides, accountingStart: day(accountingStart))
        let ledger = Ledger(sessions: sessions, workingCalendar: working, calendar: cal, now: at(now))
        return Overview(ledger: ledger, openingBalance: TimeInterval(openingMinutes * 60), today: LocalDate(at(now), calendar: cal))
    }

    @Test func dailyExampleFromSpec() {
        let o = overview(
            [session("2026-10-26T09:00:00+02:00", "2026-10-26T15:30:00+02:00")],
            now: "2026-10-26T18:00:00+02:00",
            accountingStart: "2026-10-01"
        )
        #expect(o.todayWorked == 6.5 * 3600)
        #expect(o.todayPlan.expectedMinutes == 480)
        let today = PeriodSummary(worked: o.todayWorked, expected: o.todayPlan.expected)
        #expect(today.completion == 0.8125)
        #expect(today.difference == -1.5 * 3600)
    }

    @Test func overHundredPercentAndZeroExpected() {
        #expect(PeriodSummary(worked: 42 * 3600, expected: 40 * 3600).completion == 1.05)
        #expect(PeriodSummary(worked: 2 * 3600, expected: 0).completion == nil)
        #expect(PeriodSummary(worked: 2 * 3600, expected: 0).difference == 2 * 3600)
    }

    @Test func balanceExcludesTodayAndIncludesOpeningBalance() {
        let o = overview(
            [
                session("2026-10-26T08:00:00+02:00", "2026-10-26T18:00:00+02:00"), // Mon 10h: +2h
                session("2026-10-27T09:00:00+02:00", "2026-10-27T15:00:00+02:00"), // Tue 6h: -2h
                session("2026-10-28T09:00:00+02:00", nil),                         // Wed, running
            ],
            now: "2026-10-28T10:00:00+02:00",
            accountingStart: "2026-10-26",
            openingMinutes: 90
        )
        #expect(o.balance == 1.5 * 3600)
        #expect(o.todayWorked == 3600)
        let expectedIncludingToday: TimeInterval = 5_400 + 3_600 - 28_800
        #expect(o.balanceIncludingToday == expectedIncludingToday)
    }

    @Test func balanceCarriesAcrossMonths() {
        // Accounting from Fri 30 Oct. Fri +1h, Sat +2h (no schedule), Mon 2 Nov -3h.
        let o = overview(
            [
                session("2026-10-30T08:00:00+02:00", "2026-10-30T17:00:00+02:00"),
                session("2026-10-31T10:00:00+02:00", "2026-10-31T12:00:00+02:00"),
                session("2026-11-02T09:00:00+02:00", "2026-11-02T14:00:00+02:00"),
            ],
            now: "2026-11-03T08:00:00+02:00",
            accountingStart: "2026-10-30"
        )
        #expect(o.balance == 0)
        // The month view starts fresh; only November counts there.
        #expect(o.month.toDate == PeriodSummary(worked: 5 * 3600, expected: 8 * 3600))
    }

    @Test func historyBeforeAccountingStartIsIgnored() {
        let o = overview(
            [
                session("2026-10-01T08:00:00+02:00", "2026-10-01T09:00:00+02:00"),
                session("2026-10-26T09:00:00+02:00", "2026-10-26T17:00:00+02:00"),
            ],
            now: "2026-10-27T08:00:00+02:00",
            accountingStart: "2026-10-26"
        )
        #expect(o.balance == 0)
        #expect(o.month.toDate == PeriodSummary(worked: 8 * 3600, expected: 8 * 3600))
        let fiveWorkdays: TimeInterval = 5 * 28_800
        #expect(o.month.whole.expected == fiveWorkdays)
    }

    @Test func toDateVersusWholePeriod() {
        // Thursday 29 Oct: three full days done, today in progress.
        let o = overview(
            [
                session("2026-10-26T09:00:00+02:00", "2026-10-26T17:00:00+02:00"),
                session("2026-10-27T09:00:00+02:00", "2026-10-27T17:00:00+02:00"),
                session("2026-10-28T09:00:00+02:00", "2026-10-28T17:00:00+02:00"),
                session("2026-10-29T09:00:00+02:00", "2026-10-29T11:00:00+02:00"),
            ],
            now: "2026-10-29T12:00:00+02:00",
            accountingStart: "2026-10-26"
        )
        #expect(o.week.toDate == PeriodSummary(worked: 24 * 3600, expected: 24 * 3600))
        #expect(o.week.whole == PeriodSummary(worked: 26 * 3600, expected: 40 * 3600))
        #expect(o.week.whole.completion == 0.65)
    }

    @Test func mondayHasNoToDateYet() {
        let o = overview([], now: "2026-10-26T10:00:00+02:00", accountingStart: "2026-10-01")
        #expect(o.week.toDate == .zero)
    }

    @Test func vacationRemovesExpectedTimeWithoutFakeSessions() {
        let o = overview(
            [],
            now: "2026-10-31T10:00:00+02:00",
            accountingStart: "2026-10-26",
            overrides: (26...30).map { DayOverride(date: day("2026-10-\($0)"), kind: .vacation) }
        )
        #expect(o.balance == 0)
        #expect(o.week.whole.expected == 0)
        #expect(o.week.whole.completion == nil)
    }

    @Test func midnightSessionCountsOnBothDays() {
        let byDay = WorkedTime.byDay(
            [session("2026-10-26T22:00:00+02:00", "2026-10-27T01:30:00+02:00")],
            calendar: cal,
            now: at("2026-10-28T00:00:00+02:00")
        )
        let expected: [LocalDate: TimeInterval] = [day("2026-10-26"): 7_200, day("2026-10-27"): 5_400]
        #expect(byDay == expected)
    }
}
