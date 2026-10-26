import Foundation

public enum DurationFormat {
    /// "6h 30m", "8h", "45m", "0m", "−1h 30m". Seconds are truncated, never rounded up.
    public static func hoursMinutes(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((abs(seconds) / 60).rounded(.down))
        let sign = totalMinutes > 0 && seconds < 0 ? "\u{2212}" : ""
        return sign + unsigned(totalMinutes)
    }

    /// Like `hoursMinutes`, but always shows a sign for non-zero values: "+2h 15m", "−1h 30m", "0m".
    public static func signed(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((abs(seconds) / 60).rounded(.down))
        guard totalMinutes > 0 else { return "0m" }
        return (seconds < 0 ? "\u{2212}" : "+") + unsigned(totalMinutes)
    }

    private static func unsigned(_ totalMinutes: Int) -> String {
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        switch (hours, minutes) {
        case (0, _): return "\(minutes)m"
        case (_, 0): return "\(hours)h"
        default: return "\(hours)h \(minutes)m"
        }
    }

    /// "2:14:07"
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return "\(hours):" + String(format: "%02d:%02d", minutes, secs)
    }
}

public enum PercentFormat {
    /// "81%", "105%". Rounded down so a target is never shown as met before it is.
    public static func whole(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded(.down)))%"
    }
}

public enum TimeFormat {
    /// "09:12" and "17:03", always 24-hour regardless of the system locale.
    public static func hourMinute(_ date: Date, timeZone: TimeZone = .current) -> String {
        let style = Date.VerbatimFormatStyle(
            format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            timeZone: timeZone,
            calendar: Calendar(identifier: .gregorian)
        )
        return date.formatted(style)
    }
}

public enum DateFormat {
    static let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static let monthNames = ["January", "February", "March", "April", "May", "June",
                             "July", "August", "September", "October", "November", "December"]

    /// "Monday 26 October 2026"
    public static func long(_ date: LocalDate) -> String {
        "\(weekdayNames[date.weekday.rawValue - 1]) \(date.day) \(monthNames[date.month - 1]) \(date.year)"
    }

    /// "October 2026"
    public static func monthYear(_ date: LocalDate) -> String {
        "\(monthNames[date.month - 1]) \(date.year)"
    }

    /// "October"
    public static func month(_ date: LocalDate) -> String {
        monthNames[date.month - 1]
    }

    /// "26 Oct – 1 Nov 2026", or "5 – 11 Oct 2026" within one month.
    public static func range(_ first: LocalDate, _ last: LocalDate) -> String {
        let short = { (d: LocalDate) in String(monthNames[d.month - 1].prefix(3)) }
        if first.month == last.month && first.year == last.year {
            return "\(first.day) \u{2013} \(last.day) \(short(last)) \(last.year)"
        }
        let firstYear = first.year == last.year ? "" : " \(first.year)"
        return "\(first.day) \(short(first))\(firstYear) \u{2013} \(last.day) \(short(last)) \(last.year)"
    }

    /// "Mon 26.10", European order regardless of locale.
    public static func weekdayDayMonth(_ date: LocalDate) -> String {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return String(format: "%@ %02d.%02d", names[date.weekday.rawValue - 1], date.day, date.month)
    }

    /// "26.10.2026"
    public static func dayMonthYear(_ date: LocalDate) -> String {
        String(format: "%02d.%02d.%04d", date.day, date.month, date.year)
    }
}
