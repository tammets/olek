import Foundation

public struct ReminderSettings: Codable, Equatable, Sendable {
    public var idleReminderEnabled: Bool
    public var idleThresholdMinutes: Int
    public var activeReminderEnabled: Bool
    public var activeThresholdMinutes: Int
    public var snoozeMinutes: Int
    public var minimumSpacingMinutes: Int
    /// Sleep or downtime of at least this long stops a running session at its start.
    public var autoStopHours: Int

    public init(
        idleReminderEnabled: Bool = true,
        idleThresholdMinutes: Int = 15,
        activeReminderEnabled: Bool = true,
        activeThresholdMinutes: Int = 10,
        snoozeMinutes: Int = 15,
        minimumSpacingMinutes: Int = 30,
        autoStopHours: Int = 4
    ) {
        self.idleReminderEnabled = idleReminderEnabled
        self.idleThresholdMinutes = idleThresholdMinutes
        self.activeReminderEnabled = activeReminderEnabled
        self.activeThresholdMinutes = activeThresholdMinutes
        self.snoozeMinutes = snoozeMinutes
        self.minimumSpacingMinutes = minimumSpacingMinutes
        self.autoStopHours = autoStopHours
    }

    // Missing keys fall back to defaults so settings saved by older versions keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ReminderSettings()
        idleReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .idleReminderEnabled) ?? d.idleReminderEnabled
        idleThresholdMinutes = try c.decodeIfPresent(Int.self, forKey: .idleThresholdMinutes) ?? d.idleThresholdMinutes
        activeReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .activeReminderEnabled) ?? d.activeReminderEnabled
        activeThresholdMinutes = try c.decodeIfPresent(Int.self, forKey: .activeThresholdMinutes) ?? d.activeThresholdMinutes
        snoozeMinutes = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? d.snoozeMinutes
        minimumSpacingMinutes = try c.decodeIfPresent(Int.self, forKey: .minimumSpacingMinutes) ?? d.minimumSpacingMinutes
        autoStopHours = try c.decodeIfPresent(Int.self, forKey: .autoStopHours) ?? d.autoStopHours
    }

    public var recoveryPolicy: RecoveryPolicy {
        RecoveryPolicy(
            askThreshold: TimeInterval(idleThresholdMinutes * 60),
            autoStopThreshold: TimeInterval(autoStopHours * 3600)
        )
    }
}

public enum Reminder: Equatable, Sendable {
    /// Tracking is running but nobody has touched the Mac since `idleSince`.
    case idleWhileTracking(idleSince: Date)
    /// The Mac has been in continuous use since `activeSince` while tracking is stopped.
    case activeWhileStopped(activeSince: Date)

    public var kind: ReminderEngine.Kind {
        switch self {
        case .idleWhileTracking: .idle
        case .activeWhileStopped: .active
        }
    }
}

/// Turns periodic "seconds since last input" samples into reminders.
///
/// Uses only how long ago the last keyboard, mouse, or trackpad input happened; nothing about
/// what was typed or shown. Each reminder fires once, then waits for a meaningful change before
/// it can fire again, so it never nags.
public struct ReminderEngine: Sendable {
    public enum Kind: Hashable, Sendable {
        case idle, active
    }

    /// Input arriving within this gap still counts as one continuous stretch of activity.
    public static let activityGap: TimeInterval = 120

    public var settings: ReminderSettings

    private var lastSample: Date?
    private var streakStart: Date?
    /// The idle reminder re-arms once activity resumes.
    private var idleArmed = true
    /// The active reminder re-arms after the person has been away for an idle period.
    private var activeArmed = true
    private var snoozedUntil: [Kind: Date] = [:]
    private var lastFired: [Kind: Date] = [:]

    public init(settings: ReminderSettings) {
        self.settings = settings
    }

    private var idleThreshold: TimeInterval { TimeInterval(settings.idleThresholdMinutes * 60) }
    private var activeThreshold: TimeInterval { TimeInterval(settings.activeThresholdMinutes * 60) }

    /// Feeds one sample. `workExpected` gates the active reminder: it only makes sense on a
    /// scheduled workday whose target is not met yet.
    public mutating func sample(now: Date, idleSeconds: TimeInterval, isTracking: Bool, workExpected: Bool) -> Reminder? {
        if let last = lastSample {
            let gap = now.timeIntervalSince(last)
            // Sleep or a stalled process: nothing is known about that stretch, so it is no streak.
            if gap > Self.activityGap { streakStart = nil }
            if gap >= idleThreshold { activeArmed = true }
        }
        lastSample = now

        let lastInput = now.addingTimeInterval(-max(0, idleSeconds))
        if idleSeconds < Self.activityGap {
            if streakStart == nil { streakStart = lastInput }
            idleArmed = true
        } else {
            streakStart = nil
        }
        if idleSeconds >= idleThreshold { activeArmed = true }

        if isTracking {
            guard settings.idleReminderEnabled, idleArmed, idleSeconds >= idleThreshold, canFire(.idle, now) else { return nil }
            idleArmed = false
            lastFired[.idle] = now
            return .idleWhileTracking(idleSince: lastInput)
        } else {
            guard settings.activeReminderEnabled, workExpected, activeArmed,
                  let start = streakStart, now.timeIntervalSince(start) >= activeThreshold,
                  canFire(.active, now) else { return nil }
            activeArmed = false
            lastFired[.active] = now
            return .activeWhileStopped(activeSince: start)
        }
    }

    /// "Remind me later": the same reminder may fire again once the snooze ends.
    public mutating func snooze(_ kind: Kind, now: Date) {
        snoozedUntil[kind] = now.addingTimeInterval(TimeInterval(settings.snoozeMinutes * 60))
        lastFired[kind] = nil
        switch kind {
        case .idle: idleArmed = true
        case .active: activeArmed = true
        }
    }

    /// "Not working": stay quiet until the person has been away and comes back.
    public mutating func dismissActive() {
        activeArmed = false
    }

    /// A deliberate stop is followed by personal use often enough that the active reminder
    /// waits for an idle period before it can fire.
    public mutating func trackingStopped() {
        activeArmed = false
    }

    private func canFire(_ kind: Kind, _ now: Date) -> Bool {
        if let until = snoozedUntil[kind], now < until { return false }
        if let last = lastFired[kind], now.timeIntervalSince(last) < TimeInterval(settings.minimumSpacingMinutes * 60) {
            return false
        }
        return true
    }
}

public enum TimeParse {
    /// Parses a clock time typed by a person ("9:15", "09.15", "915", "9") as that time on the
    /// same local day as `reference`. Returns nil for anything that is not a valid time.
    public static func time(_ text: String, sameDayAs reference: Date, calendar: Calendar) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(whereSeparator: { ":.".contains($0) })
        let hour: Int?
        let minute: Int?
        switch (parts.count, trimmed.count) {
        case (2, _):
            hour = Int(parts[0])
            minute = parts[1].count == 2 ? Int(parts[1]) : nil
        case (1, 1...2):
            hour = Int(trimmed)
            minute = 0
        case (1, 3...4):
            hour = Int(trimmed.dropLast(2))
            minute = Int(trimmed.suffix(2))
        default:
            return nil
        }
        guard let hour, let minute, (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let day = LocalDate(reference, calendar: calendar)
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute))
    }
}
