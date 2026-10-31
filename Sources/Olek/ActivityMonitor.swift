import CoreGraphics

enum ActivityMonitor {
    /// Seconds since the last keyboard, mouse, or trackpad input anywhere in the login session.
    /// Needs no permission and reveals nothing about what the input was.
    static func secondsSinceLastInput() -> Double {
        // kCGAnyInputEventType (~0) is not a case of the imported enum, so it is built from its raw bits.
        let anyInput = unsafeBitCast(UInt32.max, to: CGEventType.self)
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    /// Whether any display is on. False with the lid closed, after display sleep, and during the
    /// background maintenance wakes macOS performs while asleep, when the idle time is unreliable.
    static func screensAwake() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsAsleep($0) == 0 }
    }
}
