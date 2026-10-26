import Foundation

/// Decides what to do with an open session after a liveness gap: system sleep, crash,
/// force quit, reboot, or any other stretch during which the app could not record heartbeats.
public struct RecoveryPolicy: Sendable {
    /// Gaps shorter than this are ignored.
    public var askThreshold: TimeInterval
    /// Gaps at least this long stop the session at the start of the gap.
    public var autoStopThreshold: TimeInterval

    public init(askThreshold: TimeInterval = 15 * 60, autoStopThreshold: TimeInterval = 4 * 3600) {
        self.askThreshold = askThreshold
        self.autoStopThreshold = autoStopThreshold
    }

    public enum Decision: Equatable, Sendable {
        case continueSilently
        case ask(gapStart: Date, gapEnd: Date)
        case autoStop(at: Date)
    }

    public func evaluate(lastAlive: Date, now: Date) -> Decision {
        let gap = now.timeIntervalSince(lastAlive)
        // A negative gap means the clock moved backwards; nothing sensible to recover.
        if gap < askThreshold { return .continueSilently }
        if gap < autoStopThreshold { return .ask(gapStart: lastAlive, gapEnd: now) }
        return .autoStop(at: lastAlive)
    }
}
