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
