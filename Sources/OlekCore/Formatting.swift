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
