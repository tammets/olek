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

@Suite struct HistoryLedgerTests {
    let cal = calendar()

    func ledger(_ sessions: [Session], now: String, overrides: [DayOverride] = []) -> Ledger {
        let working = WorkingCalendar(settings: WorkSettings(), overrides: overrides, accountingStart: day("2026-10-01"))
        return Ledger(sessions: sessions, workingCalendar: working, calendar: cal, now: at(now))
    }

    @Test func pastPeriodToDateStopsAtItsEnd() {
        let l = ledger(
            [
                Session(id: 1, start: at("2026-10-30T09:00:00+02:00"), end: at("2026-10-30T17:00:00+02:00")),
                Session(id: 2, start: at("2026-11-02T09:00:00+02:00"), end: at("2026-11-02T19:00:00+02:00")),
            ],
            now: "2026-11-03T08:00:00+02:00"
        )
        let october = PeriodProgress(first: day("2026-10-01"), last: day("2026-10-31"), today: day("2026-11-03"), ledger: l)
        #expect(october.toDate == october.whole)
        #expect(october.whole.worked == 8 * 3600)
        #expect(october.whole.expected == 176 * 3600)
    }

    @Test func futurePeriodHasNothingYet() {
        let l = ledger([], now: "2026-10-26T10:00:00+02:00")
        let december = PeriodProgress(first: day("2026-12-01"), last: day("2026-12-31"), today: day("2026-10-26"), ledger: l)
        #expect(december.toDate == .zero)
        #expect(december.whole == PeriodSummary(worked: 0, expected: 162 * 3600))
    }

    @Test func dayStatuses() {
        let l = ledger(
            [
                Session(id: 1, start: at("2026-10-19T09:00:00+03:00"), end: at("2026-10-19T17:00:00+03:00")),
                Session(id: 2, start: at("2026-10-20T09:00:00+03:00"), end: at("2026-10-20T12:00:00+03:00")),
                Session(id: 3, start: at("2026-10-24T10:00:00+03:00"), end: at("2026-10-24T11:00:00+03:00")),
                Session(id: 4, start: at("2026-10-26T09:00:00+02:00"), end: nil),
            ],
            now: "2026-10-26T11:00:00+02:00",
            overrides: [DayOverride(date: day("2026-10-22"), kind: .vacation)]
        )
        let today = day("2026-10-26")
        #expect(l.status(on: day("2026-09-30"), today: today) == .beforeAccounting)
        #expect(l.status(on: day("2026-10-19"), today: today) == .met)
        #expect(l.status(on: day("2026-10-20"), today: today) == .below)
        #expect(l.status(on: day("2026-10-21"), today: today) == .noRecord)
        #expect(l.status(on: day("2026-10-22"), today: today) == .nonWorking)
        #expect(l.status(on: day("2026-10-24"), today: today) == .met)
        #expect(l.status(on: day("2026-10-25"), today: today) == .nonWorking)
        #expect(l.status(on: today, today: today) == .inProgress)
        #expect(l.status(on: day("2026-10-27"), today: today) == .future)
    }

    @Test func updatingTheClockOnlyMovesOpenSessions() {
        let l = ledger(
            [
                Session(id: 1, start: at("2026-10-26T08:00:00+02:00"), end: at("2026-10-26T09:00:00+02:00")),
                Session(id: 2, start: at("2026-10-26T10:00:00+02:00"), end: nil),
            ],
            now: "2026-10-26T11:00:00+02:00"
        )
        #expect(l.worked(on: day("2026-10-26")) == 2 * 3600)
        #expect(l.updated(now: at("2026-10-26T12:30:00+02:00")).worked(on: day("2026-10-26")) == 3.5 * 3600)
    }

    @Test func basePlanIgnoresOverride() {
        let working = WorkingCalendar(
            settings: WorkSettings(),
            overrides: [DayOverride(date: day("2026-12-23"), kind: .vacation)],
            accountingStart: day("2026-10-01")
        )
        #expect(working.plan(for: day("2026-12-23")).expectedMinutes == 0)
        #expect(working.basePlan(for: day("2026-12-23")).reason == .shortened(before: .christmasEve))
    }
}

@Suite struct DateLabelTests {
    @Test func isoWeeks() {
        #expect(day("2026-10-26").isoWeek == 44)
        #expect(day("2026-01-01").isoWeek == 1)
        #expect(day("2025-12-29").isoWeek == 1)
        #expect(day("2027-01-01").isoWeek == 53)
        #expect(day("2027-01-04").isoWeek == 1)
    }

    @Test func labels() {
        #expect(DateFormat.long(day("2026-10-26")) == "Monday 26 October 2026")
        #expect(DateFormat.monthYear(day("2026-10-26")) == "October 2026")
        #expect(DateFormat.range(day("2026-10-26"), day("2026-11-01")) == "26 Oct \u{2013} 1 Nov 2026")
        #expect(DateFormat.range(day("2026-10-05"), day("2026-10-11")) == "5 \u{2013} 11 Oct 2026")
        #expect(DateFormat.range(day("2026-12-28"), day("2027-01-03")) == "28 Dec 2026 \u{2013} 3 Jan 2027")
    }
}
