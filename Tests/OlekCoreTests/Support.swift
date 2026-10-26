import Foundation

/// Parses an ISO 8601 timestamp with an explicit offset, e.g. "2026-10-26T09:00:00+02:00".
func at(_ iso: String) -> Date {
    try! Date(iso, strategy: .iso8601)
}

let tallinn = TimeZone(identifier: "Europe/Tallinn")!

func calendar(in timeZone: TimeZone = tallinn) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
}
