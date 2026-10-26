import Foundation

public enum DurationFormat {
    /// "6h 30m", "45m", "0m", "-1h 30m". Seconds are truncated, never rounded up.
    public static func hoursMinutes(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((abs(seconds) / 60).rounded(.down))
        let sign = seconds <= -60 ? "\u{2212}" : ""
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(sign)\(hours)h \(minutes)m" : "\(sign)\(minutes)m"
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
