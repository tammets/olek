import Foundation

public struct GeneralSettings: Codable, Equatable, Sendable {
    public enum MenuBarText: String, Codable, CaseIterable, Sendable {
        case sessionWhileWorking
        case todayTotal
        case iconOnly
    }

    public var menuBarText: MenuBarText

    public init(menuBarText: MenuBarText = .sessionWhileWorking) {
        self.menuBarText = menuBarText
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent(String.self, forKey: .menuBarText)
        menuBarText = raw.flatMap(MenuBarText.init(rawValue:)) ?? .sessionWhileWorking
    }
}

public enum CSVExport {
    /// One row per session: local timestamps with UTC offset, so the file is unambiguous anywhere.
    public static func sessions(_ sessions: [Session], timeZone: TimeZone) -> String {
        var lines = ["id,start,end,duration_minutes,note"]
        for session in sessions {
            let duration = session.end.map { String(Int($0.timeIntervalSince(session.start) / 60)) } ?? ""
            lines.append([
                String(session.id),
                timestamp(session.start, timeZone),
                session.end.map { timestamp($0, timeZone) } ?? "",
                duration,
                field(session.note ?? ""),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One row per date from `first` through `last` with the running balance. Days before the
    /// accounting start show worked time but no expected time or balance.
    public static func dailySummary(ledger: Ledger, from first: LocalDate, through last: LocalDate, openingBalance: TimeInterval) -> String {
        var lines = ["date,weekday,day_type,expected_minutes,worked_minutes,difference_minutes,balance_minutes"]
        var balance = openingBalance
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        for date in first.through(last) {
            let plan = ledger.plan(for: date)
            let worked = ledger.worked(on: date)
            let accounted = plan.reason != .beforeAccounting
            if accounted { balance += worked - plan.expected }
            lines.append([
                date.description,
                names[date.weekday.rawValue - 1],
                field(dayType(plan)),
                accounted ? String(plan.expectedMinutes) : "",
                String(Int(worked / 60)),
                accounted ? String(Int((worked - plan.expected) / 60)) : "",
                accounted ? String(Int(balance / 60)) : "",
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func dayType(_ plan: DayPlan) -> String {
        switch plan.reason {
        case .schedule: plan.expectedMinutes > 0 ? "workday" : "non-working"
        case .holiday(let holiday): "holiday: \(holiday.name)"
        case .shortened(let holiday): "shortened before \(holiday.name)"
        case .override(let kind): kind.rawValue.replacingOccurrences(of: "_", with: " ")
        case .beforeAccounting: "before accounting"
        }
    }

    public static func timestamp(_ date: Date, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
        return formatter.string(from: date)
    }

    /// Quotes a field when it contains a comma, quote, or line break (RFC 4180).
    static func field(_ value: String) -> String {
        guard value.contains(where: { ",\"\n\r".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

public enum DurationParse {
    /// Parses a signed duration typed by a person into minutes:
    /// "1:30", "-1:30", "+2", "2.5", "2,5", "2h 15m", "45m", "-3h".
    public static func minutes(_ text: String) -> Int? {
        var s = text.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "\u{2212}", with: "-")
        var sign = 1
        if s.hasPrefix("-") { sign = -1; s.removeFirst() } else if s.hasPrefix("+") { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespaces)
        // Only one sign is allowed; "--1" must not become +1 hour via the decimal parser.
        guard let first = s.first, first.isNumber else { return nil }

        if s.contains("h") || s.contains("m") {
            let pattern = /^(?:(\d+)\s*h)?\s*(?:(\d+)\s*m)?$/
            guard let match = s.wholeMatch(of: pattern), match.1 != nil || match.2 != nil else { return nil }
            let hours = match.1.flatMap { Int($0) } ?? 0
            let minutes = match.2.flatMap { Int($0) } ?? 0
            return sign * (hours * 60 + minutes)
        }
        if s.contains(":") {
            let parts = s.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let hours = Int(parts[0]), parts[1].count == 2,
                  let minutes = Int(parts[1]), minutes < 60 else { return nil }
            return sign * (hours * 60 + minutes)
        }
        guard let hours = Double(s.replacingOccurrences(of: ",", with: ".")), hours.isFinite else { return nil }
        return sign * Int((hours * 60).rounded())
    }
}
