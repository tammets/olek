import Foundation

/// A calendar date with no time or time zone, e.g. 2026-10-26.
///
/// Holiday rules and expected hours are defined per calendar date, so they are computed on this
/// type with pure integer arithmetic. Conversion to real time happens only through `interval(in:)`.
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year!, month: components.month!, day: components.day!)
    }

    /// Parses "YYYY-MM-DD".
    public init?(_ string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
        guard LocalDate(julianDay: julianDay) == self else { return nil }
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        lhs.julianDay < rhs.julianDay
    }

    public func adding(days: Int) -> LocalDate {
        LocalDate(julianDay: julianDay + days)
    }

    public func days(until other: LocalDate) -> Int {
        other.julianDay - julianDay
    }

    public var weekday: Weekday {
        // Julian day 0 was a Monday.
        Weekday(rawValue: julianDay % 7 + 1)!
    }

    /// ISO 8601 week number. Week 1 is the week containing the year's first Thursday.
    public var isoWeek: Int {
        let thursday = adding(days: Weekday.thursday.rawValue - weekday.rawValue)
        return LocalDate(year: thursday.year, month: 1, day: 1).days(until: thursday) / 7 + 1
    }

    public var startOfWeek: LocalDate { adding(days: -(weekday.rawValue - 1)) }
    public var startOfMonth: LocalDate { LocalDate(year: year, month: month, day: 1) }
    public var endOfMonth: LocalDate {
        let next = month == 12 ? LocalDate(year: year + 1, month: 1, day: 1) : LocalDate(year: year, month: month + 1, day: 1)
        return next.adding(days: -1)
    }
    public var startOfYear: LocalDate { LocalDate(year: year, month: 1, day: 1) }
    public var endOfYear: LocalDate { LocalDate(year: year, month: 12, day: 31) }

    /// The real-time span of this date in `calendar`'s time zone. 23 or 25 hours on DST change days.
    public func interval(in calendar: Calendar) -> DateInterval {
        // Anchoring at noon avoids zones where midnight itself is skipped by a DST change.
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        return calendar.dateInterval(of: .day, for: noon)!
    }

    /// Inclusive sequence of dates from `self` through `last`.
    public func through(_ last: LocalDate) -> [LocalDate] {
        guard self <= last else { return [] }
        return (julianDay...last.julianDay).map(LocalDate.init(julianDay:))
    }

    // Fliegel and Van Flandern conversion for the proleptic Gregorian calendar.
    var julianDay: Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    init(julianDay: Int) {
        let a = julianDay + 32044
        let b = (4 * a + 3) / 146097
        let c = a - 146097 * b / 4
        let d = (4 * c + 3) / 1461
        let e = c - 1461 * d / 4
        let m = (5 * e + 2) / 153
        self.init(
            year: 100 * b + d - 4800 + m / 10,
            month: m + 3 - 12 * (m / 10),
            day: e - (153 * m + 2) / 5 + 1
        )
    }
}

extension LocalDate: Codable {
    public init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let date = LocalDate(string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date \(string)"))
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// ISO weekday numbering, Monday first.
public enum Weekday: Int, CaseIterable, Sendable, Codable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday
}
