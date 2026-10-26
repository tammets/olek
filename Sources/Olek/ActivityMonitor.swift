import CoreGraphics

enum ActivityMonitor {
    /// Seconds since the last keyboard, mouse, or trackpad input anywhere in the login session.
    /// Needs no permission and reveals nothing about what the input was.
    static func secondsSinceLastInput() -> Double {
        // kCGAnyInputEventType (~0) is not a case of the imported enum, so it is built from its raw bits.
        let anyInput = unsafeBitCast(UInt32.max, to: CGEventType.self)
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
