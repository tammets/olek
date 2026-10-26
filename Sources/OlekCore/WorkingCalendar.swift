import Foundation

public struct WorkSettings: Codable, Equatable, Sendable {
    /// Expected minutes for each weekday, Monday first.
    public var minutesByWeekday: [Int]
    public var estonianHolidays: Bool
    public var shortenedDays: Bool
    /// First day that counts toward the balance. `nil` means the date of first launch.
    public var accountingStart: LocalDate?
    public var openingBalanceMinutes: Int

    public static let standardWeek = [480, 480, 480, 480, 480, 0, 0]

    public init(
        minutesByWeekday: [Int] = WorkSettings.standardWeek,
        estonianHolidays: Bool = true,
        shortenedDays: Bool = true,
        accountingStart: LocalDate? = nil,
        openingBalanceMinutes: Int = 0
    ) {
        self.minutesByWeekday = minutesByWeekday
        self.estonianHolidays = estonianHolidays
        self.shortenedDays = shortenedDays
        self.accountingStart = accountingStart
        self.openingBalanceMinutes = openingBalanceMinutes
    }

    // Missing keys fall back to defaults so settings saved by older versions keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = WorkSettings()
        let minutes = try c.decodeIfPresent([Int].self, forKey: .minutesByWeekday)
        minutesByWeekday = minutes?.count == 7 ? minutes! : defaults.minutesByWeekday
        estonianHolidays = try c.decodeIfPresent(Bool.self, forKey: .estonianHolidays) ?? defaults.estonianHolidays
        shortenedDays = try c.decodeIfPresent(Bool.self, forKey: .shortenedDays) ?? defaults.shortenedDays
        accountingStart = try c.decodeIfPresent(LocalDate.self, forKey: .accountingStart)
        openingBalanceMinutes = try c.decodeIfPresent(Int.self, forKey: .openingBalanceMinutes) ?? defaults.openingBalanceMinutes
    }

    public func scheduledMinutes(on weekday: Weekday) -> Int {
        minutesByWeekday[weekday.rawValue - 1]
    }
}

public struct DayOverride: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case vacation
        case dayOff = "day_off"
        case sick
        case customNonWorking = "custom_off"
        case customWorking = "custom_on"
        /// A different number of expected minutes, e.g. a half day.
        case minutes
    }

    public var date: LocalDate
    public var kind: Kind
    /// Required for `.customWorking` and `.minutes`, ignored otherwise.
    public var expectedMinutes: Int?
    public var note: String?

    public init(date: LocalDate, kind: Kind, expectedMinutes: Int? = nil, note: String? = nil) {
        self.date = date
        self.kind = kind
        self.expectedMinutes = expectedMinutes
        self.note = note
    }
}

public struct DayPlan: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case schedule
        case holiday(EstonianHoliday)
        case shortened(before: EstonianHoliday)
        case override(DayOverride.Kind)
        case beforeAccounting
    }

    public var date: LocalDate
    public var expectedMinutes: Int
    public var reason: Reason

    public init(date: LocalDate, expectedMinutes: Int, reason: Reason) {
        self.date = date
        self.expectedMinutes = expectedMinutes
        self.reason = reason
    }

    public var expected: TimeInterval { TimeInterval(expectedMinutes * 60) }
}

/// Expected working time per date. Rules, first match wins:
///
/// 1. Dates before the accounting start expect nothing.
/// 2. A personal override for the date.
/// 3. An Estonian public holiday expects nothing.
/// 4. A shortened pre-holiday day expects the scheduled time minus three hours.
/// 5. The weekly schedule.
public struct WorkingCalendar: Sendable {
    public static let shortenedDayReductionMinutes = 180

    public var settings: WorkSettings
    public var overrides: [LocalDate: DayOverride]
    public var accountingStart: LocalDate

    public init(settings: WorkSettings, overrides: [DayOverride] = [], accountingStart: LocalDate) {
        self.settings = settings
        self.overrides = Dictionary(overrides.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
        self.accountingStart = accountingStart
    }

    public func plan(for date: LocalDate) -> DayPlan {
        if date < accountingStart {
            return DayPlan(date: date, expectedMinutes: 0, reason: .beforeAccounting)
        }
        if let override = overrides[date] {
            let minutes = switch override.kind {
            case .vacation, .dayOff, .sick, .customNonWorking: 0
            case .customWorking, .minutes: max(0, override.expectedMinutes ?? 0)
            }
            return DayPlan(date: date, expectedMinutes: minutes, reason: .override(override.kind))
        }
        if settings.estonianHolidays, let holiday = EstonianHoliday.holiday(on: date) {
            return DayPlan(date: date, expectedMinutes: 0, reason: .holiday(holiday))
        }
        let scheduled = settings.scheduledMinutes(on: date.weekday)
        if settings.estonianHolidays, settings.shortenedDays, scheduled > 0,
           let holiday = EstonianHoliday.shortenedDay(on: date) {
            let minutes = max(0, scheduled - Self.shortenedDayReductionMinutes)
            return DayPlan(date: date, expectedMinutes: minutes, reason: .shortened(before: holiday))
        }
        return DayPlan(date: date, expectedMinutes: scheduled, reason: .schedule)
    }
}
