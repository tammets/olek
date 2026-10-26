import Foundation
import Testing
import OlekCore

@Suite struct LocalDateTests {
    @Test func parsesAndRejects() {
        #expect(LocalDate("2026-10-26") == LocalDate(year: 2026, month: 10, day: 26))
        #expect(LocalDate("2026-02-30") == nil)
        #expect(LocalDate("2026-13-01") == nil)
        #expect(LocalDate("nonsense") == nil)
    }

    @Test func weekdays() {
        #expect(day("2000-01-01").weekday == .saturday)
        #expect(day("2026-10-26").weekday == .monday)
        #expect(day("2026-12-24").weekday == .thursday)
    }

    @Test func arithmeticCrossesMonthsAndYears() {
        #expect(day("2026-12-31").adding(days: 1) == day("2027-01-01"))
        #expect(day("2028-03-01").adding(days: -1) == day("2028-02-29"))
        #expect(day("2026-02-10").endOfMonth == day("2026-02-28"))
        #expect(day("2026-10-29").startOfWeek == day("2026-10-26"))
        #expect(day("2026-11-01").startOfWeek == day("2026-10-26"))
        #expect(day("2026-01-01").through(day("2026-12-31")).count == 365)
    }

    @Test func intervalFollowsLocalTimeZone() {
        let interval = day("2026-10-25").interval(in: calendar())
        #expect(interval.start == at("2026-10-25T00:00:00+03:00"))
        #expect(interval.duration == 25 * 3600)
    }

    @Test func codableAsPlainString() throws {
        let data = try JSONEncoder().encode([day("2026-10-26")])
        #expect(String(decoding: data, as: UTF8.self) == #"["2026-10-26"]"#)
        #expect(try JSONDecoder().decode([LocalDate].self, from: data) == [day("2026-10-26")])
    }
}

@Suite struct EstonianHolidayTests {
    @Test(arguments: [
        ("2008-03-23", 2008), ("2019-04-21", 2019), ("2024-03-31", 2024), ("2025-04-20", 2025),
        ("2026-04-05", 2026), ("2027-03-28", 2027), ("2038-04-25", 2038), ("2285-03-22", 2285),
    ])
    func easter(expected: String, year: Int) {
        #expect(EstonianHoliday.easterSunday(year: year) == day(expected))
    }

    @Test func allHolidaysOf2026() {
        let holidays = EstonianHoliday.holidays(in: 2026)
        #expect(holidays.map(\.date.description) == [
            "2026-01-01", "2026-02-24", "2026-04-03", "2026-04-05", "2026-05-01", "2026-05-24",
            "2026-06-23", "2026-06-24", "2026-08-20", "2026-12-24", "2026-12-25", "2026-12-26",
        ])
        #expect(Set(holidays.map(\.holiday)) == Set(EstonianHoliday.allCases))
    }

    @Test func movingHolidaysIn2027() {
        #expect(EstonianHoliday.holiday(on: day("2027-03-26")) == .goodFriday)
        #expect(EstonianHoliday.holiday(on: day("2027-05-16")) == .pentecost)
    }

    @Test func shortenedDaysAreTheCalendarDayBefore() {
        #expect(EstonianHoliday.shortenedDay(on: day("2026-12-31")) == .newYearsDay)
        #expect(EstonianHoliday.shortenedDay(on: day("2026-02-23")) == .independenceDay)
        #expect(EstonianHoliday.shortenedDay(on: day("2026-06-22")) == .victoryDay)
        #expect(EstonianHoliday.shortenedDay(on: day("2026-12-23")) == .christmasEve)
        // Christmas Eve precedes Christmas Day, which does not shorten anything.
        #expect(EstonianHoliday.shortenedDay(on: day("2026-12-24")) == nil)
        #expect(EstonianHoliday.shortenedDay(on: day("2026-06-23")) == nil)
    }
}

@Suite struct WorkingCalendarTests {
    let calendar2026 = WorkingCalendar(settings: WorkSettings(), accountingStart: day("2020-01-01"))

    func expectedHours(_ cal: WorkingCalendar, _ first: String, _ last: String) -> Double {
        day(first).through(day(last)).reduce(0) { $0 + Double(cal.plan(for: $1).expectedMinutes) } / 60
    }

    @Test func normalWeek() {
        #expect(expectedHours(calendar2026, "2026-10-26", "2026-11-01") == 40)
        #expect(calendar2026.plan(for: day("2026-10-31")).expectedMinutes == 0)
    }

    @Test func holidayWeekWithShortenedMonday() {
        // Mon 22 Jun shortened to 5h, Tue 23 and Wed 24 holidays, Thu and Fri 8h each.
        #expect(expectedHours(calendar2026, "2026-06-22", "2026-06-28") == 21)
        #expect(calendar2026.plan(for: day("2026-06-22")).reason == .shortened(before: .victoryDay))
        #expect(calendar2026.plan(for: day("2026-06-23")).reason == .holiday(.victoryDay))
    }

    @Test func monthlyTotals() {
        #expect(expectedHours(calendar2026, "2026-10-01", "2026-10-31") == 176)
        // 21 working days, with 23 and 31 December shortened by three hours.
        #expect(expectedHours(calendar2026, "2026-12-01", "2026-12-31") == 162)
    }

    @Test func yearlyTotal2026() {
        #expect(expectedHours(calendar2026, "2026-01-01", "2026-12-31") == 2004)
    }

    @Test func holidayOnMondayDoesNotShortenFriday() {
        // Independence Day 2025 was a Monday. Sunday the 23rd is the day that would be shortened.
        let cal = WorkingCalendar(settings: WorkSettings(), accountingStart: day("2020-01-01"))
        #expect(cal.plan(for: day("2025-02-21")) == DayPlan(date: day("2025-02-21"), expectedMinutes: 480, reason: .schedule))
        #expect(cal.plan(for: day("2025-02-23")).expectedMinutes == 0)
    }

    @Test func weekendWorkerGetsWeekendShortening() {
        var settings = WorkSettings()
        settings.minutesByWeekday = [480, 480, 480, 480, 480, 0, 480]
        let cal = WorkingCalendar(settings: settings, accountingStart: day("2020-01-01"))
        #expect(cal.plan(for: day("2025-02-23")).expectedMinutes == 300)
    }

    @Test func partTimeShortenedDayNeverGoesNegative() {
        var settings = WorkSettings()
        settings.minutesByWeekday = [120, 120, 120, 120, 120, 0, 0]
        let cal = WorkingCalendar(settings: settings, accountingStart: day("2020-01-01"))
        #expect(cal.plan(for: day("2026-12-23")).expectedMinutes == 0)
    }

    @Test func overridePrecedence() {
        let cal = WorkingCalendar(
            settings: WorkSettings(),
            overrides: [
                DayOverride(date: day("2026-12-23"), kind: .vacation),
                DayOverride(date: day("2026-12-24"), kind: .minutes, expectedMinutes: 240),
                DayOverride(date: day("2026-10-31"), kind: .customWorking, expectedMinutes: 360),
                DayOverride(date: day("2026-10-27"), kind: .sick),
                DayOverride(date: day("2026-10-28"), kind: .minutes, expectedMinutes: 240),
            ],
            accountingStart: day("2020-01-01")
        )
        #expect(cal.plan(for: day("2026-12-23")).expectedMinutes == 0)
        #expect(cal.plan(for: day("2026-12-24")).expectedMinutes == 240)
        #expect(cal.plan(for: day("2026-10-31")).expectedMinutes == 360)
        #expect(cal.plan(for: day("2026-10-27")).reason == .override(.sick))
        #expect(cal.plan(for: day("2026-10-28")).expectedMinutes == 240)
    }

    @Test func holidaysCanBeTurnedOff() {
        var settings = WorkSettings()
        settings.estonianHolidays = false
        let cal = WorkingCalendar(settings: settings, accountingStart: day("2020-01-01"))
        #expect(cal.plan(for: day("2026-12-24")).expectedMinutes == 480)
        #expect(cal.plan(for: day("2026-12-23")).expectedMinutes == 480)
    }

    @Test func beforeAccountingStartExpectsNothing() {
        let cal = WorkingCalendar(settings: WorkSettings(), accountingStart: day("2026-10-26"))
        #expect(cal.plan(for: day("2026-10-23")).reason == .beforeAccounting)
        #expect(cal.plan(for: day("2026-10-26")).expectedMinutes == 480)
    }

    @Test func settingsDecodeWithMissingKeys() throws {
        let settings = try JSONDecoder().decode(WorkSettings.self, from: Data(#"{"openingBalanceMinutes": 90}"#.utf8))
        #expect(settings.openingBalanceMinutes == 90)
        #expect(settings.minutesByWeekday == WorkSettings.standardWeek)
        #expect(settings.estonianHolidays)
    }
}
