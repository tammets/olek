import Foundation

public struct PeriodSummary: Equatable, Sendable {
    public var worked: TimeInterval
    public var expected: TimeInterval

    public init(worked: TimeInterval = 0, expected: TimeInterval = 0) {
        self.worked = worked
        self.expected = expected
    }

    public static let zero = PeriodSummary()

    public var difference: TimeInterval { worked - expected }

    /// `nil` when nothing was expected; a percentage would be meaningless.
    public var completion: Double? { expected > 0 ? worked / expected : nil }
}

/// Worked and expected time per date, the single source for every period figure.
public struct Ledger: Sendable {
    public let workingCalendar: WorkingCalendar
    public let workedByDay: [LocalDate: TimeInterval]

    public init(sessions: [Session], workingCalendar: WorkingCalendar, calendar: Calendar, now: Date) {
        self.workingCalendar = workingCalendar
        self.workedByDay = WorkedTime.byDay(sessions, calendar: calendar, now: now)
    }

    public func worked(on date: LocalDate) -> TimeInterval {
        workedByDay[date] ?? 0
    }

    /// Sums accounted days from `first` through `last`. Days before the accounting start are skipped
    /// entirely, so the balance never mixes in history from before it began.
    public func summary(from first: LocalDate, through last: LocalDate) -> PeriodSummary {
        let start = max(first, workingCalendar.accountingStart)
        return start.through(last).reduce(into: PeriodSummary()) { total, date in
            total.worked += worked(on: date)
            total.expected += workingCalendar.plan(for: date).expected
        }
    }
}

public struct PeriodProgress: Equatable, Sendable {
    public var first: LocalDate
    public var last: LocalDate
    /// From the start of the period through yesterday. Today is still in progress, so it is left out.
    public var toDate: PeriodSummary
    /// Everything worked so far, including today, against the whole period's expected time.
    public var whole: PeriodSummary

    init(first: LocalDate, last: LocalDate, today: LocalDate, ledger: Ledger) {
        self.first = first
        self.last = last
        let yesterday = today.adding(days: -1)
        toDate = yesterday >= first ? ledger.summary(from: first, through: yesterday) : .zero
        whole = PeriodSummary(
            worked: ledger.summary(from: first, through: today).worked,
            expected: ledger.summary(from: first, through: last).expected
        )
    }
}

/// Everything the menu bar popover shows, computed from sessions and settings.
public struct Overview: Equatable, Sendable {
    public var today: LocalDate
    public var todayPlan: DayPlan
    public var todayWorked: TimeInterval
    public var week: PeriodProgress
    public var month: PeriodProgress
    public var year: PeriodProgress
    public var accountingStart: LocalDate
    /// Opening balance plus every accounted day through yesterday.
    public var balance: TimeInterval
    public var balanceIncludingToday: TimeInterval

    public init(ledger: Ledger, openingBalance: TimeInterval, today: LocalDate) {
        self.today = today
        todayPlan = ledger.workingCalendar.plan(for: today)
        todayWorked = ledger.worked(on: today)
        week = PeriodProgress(first: today.startOfWeek, last: today.startOfWeek.adding(days: 6), today: today, ledger: ledger)
        month = PeriodProgress(first: today.startOfMonth, last: today.endOfMonth, today: today, ledger: ledger)
        year = PeriodProgress(first: today.startOfYear, last: today.endOfYear, today: today, ledger: ledger)
        accountingStart = ledger.workingCalendar.accountingStart

        let yesterday = today.adding(days: -1)
        balance = openingBalance + ledger.summary(from: accountingStart, through: yesterday).difference
        balanceIncludingToday = openingBalance + ledger.summary(from: accountingStart, through: today).difference
    }
}
