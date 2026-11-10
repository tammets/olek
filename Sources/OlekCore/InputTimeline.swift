import Foundation

/// Places the last keyboard, mouse, or trackpad input on the wall clock.
///
/// macOS reports the age of that input on a clock that stands still while the Mac sleeps. Taken
/// at face value after a sleep, "ten minutes idle" puts yesterday evening's last keystroke ten
/// minutes ago, and every background wake during the night moves it later still. So an input
/// only gets a new date while the Mac has stayed awake since it happened; after a sleep the
/// date worked out before the sleep stands until there is new input.
public struct InputTimeline: Sendable {
    private var sleptTotal: TimeInterval?
    private var lastUptime = -TimeInterval.infinity
    /// Uptime of the last sample before the latest sleep. Uptime stands still during sleep, so
    /// input older than this predates the sleep and anything newer came after the wake.
    private var awakeSince = -TimeInterval.infinity
    private var input = Date.distantPast
    /// Whether there has been input since the Mac last woke, as of the latest sample.
    public private(set) var inputSinceWake = true

    public init() {}

    /// Sample right before the Mac sleeps as well: input between the last sample and the sleep
    /// would otherwise be taken for input after the wake.
    ///
    /// - Parameters:
    ///   - uptime: seconds the Mac has been running, not counting sleep.
    ///   - sleptTotal: seconds the Mac has spent asleep since it booted.
    ///   - idleSeconds: age of the last input on the uptime clock.
    /// - Returns: when the last input happened. The first sample is taken at face value.
    public mutating func sample(
        now: Date,
        uptime: TimeInterval,
        sleptTotal: TimeInterval,
        idleSeconds: TimeInterval
    ) -> Date {
        // The two clocks are read a moment apart, so a small difference is not a sleep.
        if let before = self.sleptTotal, sleptTotal - before >= 1 { awakeSince = lastUptime }
        self.sleptTotal = sleptTotal
        lastUptime = uptime

        let idle = max(0, idleSeconds)
        inputSinceWake = uptime - idle > awakeSince
        if inputSinceWake { input = now.addingTimeInterval(-idle) }
        // The clock was set back past the stored date. Moved once, it does not keep following the clock.
        if input > now { input = now }
        return input
    }
}
