import Foundation

public struct Session: Identifiable, Hashable, Sendable {
    public let id: Int64
    public var start: Date
    /// `nil` while the session is running.
    public var end: Date?
    /// Last moment the app confirmed it was alive while this session was open.
    public var heartbeat: Date?
    public var note: String?

    public init(id: Int64, start: Date, end: Date? = nil, heartbeat: Date? = nil, note: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.heartbeat = heartbeat
        self.note = note
    }

    public var isOpen: Bool { end == nil }

    /// Latest point in time this open session is known to have been tracked.
    public var lastAlive: Date { max(heartbeat ?? start, start) }
}

public enum SessionError: Error, Equatable, LocalizedError {
    case alreadyRunning
    case notRunning
    case notFound
    case endNotAfterStart
    case inFuture
    case overlaps(with: Int64)
    case invalidExpectedMinutes
    case breakOutsideSession

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: String(localized: "A session is already running.")
        case .notRunning: String(localized: "No session is running.")
        case .notFound: String(localized: "That session no longer exists.")
        case .endNotAfterStart: String(localized: "The end time must be after the start time.")
        case .inFuture: String(localized: "Times cannot be in the future.")
        case .overlaps: String(localized: "This would overlap another session.")
        case .invalidExpectedMinutes: String(localized: "Expected hours must be between 0 and 24.")
        case .breakOutsideSession: String(localized: "The break must start after the session starts and end before it ends.")
        }
    }
}

public enum StopResult: Equatable, Sendable {
    case stopped(Session)
    /// The session would have had no duration, so it was removed instead of saved.
    case discarded(Session)
}

extension Date {
    /// Timestamps are stored as whole seconds; all comparisons use this same truncation.
    var unixSeconds: Int64 { Int64(timeIntervalSince1970.rounded(.down)) }

    init(unixSeconds: Int64) {
        self.init(timeIntervalSince1970: TimeInterval(unixSeconds))
    }
}
