import Foundation

public enum WorkedTime {
    /// Total tracked seconds inside `interval`. Open sessions count up to `now`.
    /// Sessions crossing the interval's edges contribute only the part inside it.
    public static func seconds(of sessions: [Session], in interval: DateInterval, now: Date) -> TimeInterval {
        sessions.reduce(0) { total, session in
            let end = session.end ?? max(now, session.start)
            let lower = max(session.start, interval.start)
            let upper = min(end, interval.end)
            return total + max(0, upper.timeIntervalSince(lower))
        }
    }
}

extension WorkedTime {
    /// Tracked seconds per local date. Sessions crossing midnight are split at each day boundary.
    public static func byDay(_ sessions: [Session], calendar: Calendar, now: Date) -> [LocalDate: TimeInterval] {
        var result: [LocalDate: TimeInterval] = [:]
        for session in sessions {
            let end = session.end ?? max(now, session.start)
            guard end > session.start else { continue }
            var date = LocalDate(session.start, calendar: calendar)
            while true {
                let day = date.interval(in: calendar)
                let lower = max(session.start, day.start)
                let upper = min(end, day.end)
                if upper > lower {
                    result[date, default: 0] += upper.timeIntervalSince(lower)
                }
                if day.end >= end { break }
                date = date.adding(days: 1)
            }
        }
        return result
    }
}
