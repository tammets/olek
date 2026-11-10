import CoreGraphics
import Foundation

enum ActivityMonitor {
    /// Seconds since the last keyboard, mouse, or trackpad input anywhere in the login session.
    /// Needs no permission and reveals nothing about what the input was. Time asleep is not
    /// counted, so this is only a wall-clock age while the Mac has stayed awake; see `InputTimeline`.
    static func secondsSinceLastInput() -> Double {
        // kCGAnyInputEventType (~0) is not a case of the imported enum, so it is built from its raw bits.
        let anyInput = unsafeBitCast(UInt32.max, to: CGEventType.self)
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    /// Seconds the Mac has been running without counting sleep, and seconds it has spent asleep.
    static func clocks() -> (uptime: TimeInterval, sleptTotal: TimeInterval) {
        let awake = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let total = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
        return (Double(awake) / 1e9, Double(total > awake ? total - awake : 0) / 1e9)
    }

    /// Whether any display is on. False with the lid closed and after display sleep. Background
    /// maintenance wakes can report a display as on, so this alone does not mean someone is there.
    static func screensAwake() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsAsleep($0) == 0 }
    }
}
