import Foundation

/// Decides what to do with an open session based on when the person was last seen at the Mac.
///
/// "Seen" means keyboard, mouse, or trackpad input while a screen is on. Sleep, a closed lid,
/// a dark screen, a crash, or Olek not running all leave the last sighting where it was, so they
/// count as away exactly like walking off with the screen on. Background maintenance wakes keep
/// the screens dark and so cannot make an absence look shorter than it was.
public struct RecoveryPolicy: Sendable {
    /// Absences shorter than this are ignored.
    public var askThreshold: TimeInterval
    /// Absences at least this long stop the session at the moment the person left.
    public var autoStopThreshold: TimeInterval
    /// While present, the stored sighting is refreshed at most this often, except when input pauses.
    public static let recordInterval: TimeInterval = 60

    public init(askThreshold: TimeInterval = 15 * 60, autoStopThreshold: TimeInterval = 4 * 3600) {
        self.askThreshold = askThreshold
        self.autoStopThreshold = autoStopThreshold
    }

    public enum Decision: Equatable, Sendable {
        case nothing
        /// Store `presence` as the session's last sighting.
        case record(presence: Date)
        /// The person was away from `gapStart` and came back at `gapEnd`; store `gapEnd` too.
        case ask(gapStart: Date, gapEnd: Date)
        case autoStop(at: Date)
    }

    /// - Parameters:
    ///   - lastSeen: the stored last sighting of the open session.
    ///   - presence: the latest input while a screen is on, or `nil` when the screens are dark.
    public func evaluate(lastSeen: Date, presence: Date?, now: Date) -> Decision {
        // Sightings are stored in whole seconds, so anything within a second of it is the same one.
        guard let presence, presence.timeIntervalSince(lastSeen) >= 1 else {
            // Not seen since the last sighting: still away, or present without touching anything.
            return now.timeIntervalSince(lastSeen) >= autoStopThreshold ? .autoStop(at: lastSeen) : .nothing
        }
        let gap = presence.timeIntervalSince(lastSeen)
        if gap >= autoStopThreshold { return .autoStop(at: lastSeen) }
        if gap >= askThreshold { return .ask(gapStart: lastSeen, gapEnd: presence) }
        // Once input pauses, store its last moment so an absence starting now begins exactly there.
        if gap >= Self.recordInterval || now.timeIntervalSince(presence) >= Self.recordInterval {
            return .record(presence: presence)
        }
        return .nothing
    }
}
