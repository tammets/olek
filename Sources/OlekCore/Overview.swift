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
    public let calendar: Calendar
    public private(set) var workedByDay: [LocalDate: TimeInterval]
    // Closed sessions never change with time, so they are split into days once.
    // Only open sessions are recomputed when the clock moves.
    private let closedByDay: [LocalDate: TimeInterval]
    private let openSessions: [Session]

    public init(sessions: [Session], workingCalendar: WorkingCalendar, calendar: Calendar, now: Date) {
        self.workingCalendar = workingCalendar
        self.calendar = calendar
        openSessions = sessions.filter(\.isOpen)
        closedByDay = WorkedTime.byDay(sessions.filter { !$0.isOpen }, calendar: calendar, now: now)
        workedByDay = [:]
        refreshOpenSessions(now: now)
    }

    /// The same ledger with open sessions extended to `now`.
    public func updated(now: Date) -> Ledger {
        var copy = self
        copy.refreshOpenSessions(now: now)
        return copy
    }

    private mutating func refreshOpenSessions(now: Date) {
        workedByDay = closedByDay.merging(
            WorkedTime.byDay(openSessions, calendar: calendar, now: now),
            uniquingKeysWith: +
        )
    }

    public func worked(on date: LocalDate) -> TimeInterval {
        workedByDay[date] ?? 0
    }

    public func plan(for date: LocalDate) -> DayPlan {
        workingCalendar.plan(for: date)
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

    public func status(on date: LocalDate, today: LocalDate) -> DayStatus {
        let plan = workingCalendar.plan(for: date)
        let worked = worked(on: date)
        if plan.reason == .beforeAccounting { return .beforeAccounting }
        if date > today { return .future }
        if plan.expectedMinutes == 0 { return worked > 0 ? .met : .nonWorking }
        if worked >= plan.expected { return .met }
        if date == today { return .inProgress }
        return worked > 0 ? .below : .noRecord
    }
}

public enum DayStatus: Equatable, Sendable {
    case beforeAccounting
    case future
    /// Nothing expected and nothing worked: weekend, holiday, vacation.
    case nonWorking
    /// Work expected, none recorded, day is over.
    case noRecord
    case below
    case met
    /// Today, target not reached yet.
    case inProgress
}

public struct PeriodProgress: Equatable, Sendable {
    public var first: LocalDate
    public var last: LocalDate
    /// From the start of the period through yesterday. Today is still in progress, so it is left out.
    public var toDate: PeriodSummary
    /// Everything worked so far, including today, against the whole period's expected time.
    public var whole: PeriodSummary

    /// Works for past, current, and future periods: "to date" never reaches past the period's end.
    public init(first: LocalDate, last: LocalDate, today: LocalDate, ledger: Ledger) {
        self.first = first
        self.last = last
        let toDateEnd = min(today.adding(days: -1), last)
        toDate = toDateEnd >= first ? ledger.summary(from: first, through: toDateEnd) : .zero
        let workedEnd = min(today, last)
        whole = PeriodSummary(
            worked: workedEnd >= first ? ledger.summary(from: first, through: workedEnd).worked : 0,
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
