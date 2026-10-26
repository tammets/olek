import Foundation
import Testing
@testable import OlekCore

@Suite struct CSVExportTests {
    @Test func sessionsUseLocalTimeWithOffsetAndEscapeNotes() {
        let csv = CSVExport.sessions(
            [
                Session(id: 1, start: at("2026-10-26T09:00:00+02:00"), end: at("2026-10-26T12:30:00+02:00"), note: "Client, \"Alpha\""),
                Session(id: 2, start: at("2026-10-26T13:00:00+02:00"), end: nil),
            ],
            timeZone: tallinn
        )
        #expect(csv == """
        id,start,end,duration_minutes,note
        1,2026-10-26T09:00:00+02:00,2026-10-26T12:30:00+02:00,210,"Client, ""Alpha\"""
        2,2026-10-26T13:00:00+02:00,,,

        """)
    }

    @Test func summerTimeOffsetIsWritten() {
        let csv = CSVExport.sessions([Session(id: 1, start: at("2026-07-01T09:00:00+03:00"), end: at("2026-07-01T10:00:00+03:00"))], timeZone: tallinn)
        #expect(csv.contains("2026-07-01T09:00:00+03:00"))
    }

    @Test func dailySummaryRunsTheBalance() {
        let working = WorkingCalendar(settings: WorkSettings(), accountingStart: day("2026-10-22"))
        let ledger = Ledger(
            sessions: [
                Session(id: 1, start: at("2026-10-21T09:00:00+03:00"), end: at("2026-10-21T10:00:00+03:00")),
                Session(id: 2, start: at("2026-10-22T08:00:00+03:00"), end: at("2026-10-22T18:00:00+03:00")),
                Session(id: 3, start: at("2026-10-23T09:00:00+03:00"), end: at("2026-10-23T16:00:00+03:00")),
            ],
            workingCalendar: working,
            calendar: calendar(),
            now: at("2026-10-26T12:00:00+02:00")
        )
        let csv = CSVExport.dailySummary(ledger: ledger, from: day("2026-10-21"), through: day("2026-10-24"), openingBalance: 30 * 60)
        #expect(csv == """
        date,weekday,day_type,expected_minutes,worked_minutes,difference_minutes,balance_minutes
        2026-10-21,Wed,before accounting,,60,,
        2026-10-22,Thu,workday,480,600,120,150
        2026-10-23,Fri,workday,480,420,-60,90
        2026-10-24,Sat,non-working,0,0,0,90

        """)
    }
}

@Suite struct DurationParseTests {
    @Test(arguments: [
        ("1:30", 90), ("-1:30", -90), ("\u{2212}1:30", -90), ("+2", 120), ("2.5", 150), ("2,5", 150),
        ("2h 15m", 135), ("2h15m", 135), ("45m", 45), ("-3h", -180), ("0", 0), (" 12:05 ", 725),
    ])
    func accepted(text: String, minutes: Int) {
        #expect(DurationParse.minutes(text) == minutes)
    }

    @Test(arguments: ["", "abc", "1:5", "1:75", "h", "2x", "--1"])
    func rejected(_ text: String) {
        #expect(DurationParse.minutes(text) == nil)
    }
}

@Suite struct BackupTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("olek-backup-\(UUID().uuidString)")

    func store(_ name: String) throws -> SessionStore {
        try SessionStore(url: folder.appendingPathComponent(name), now: at("2026-10-01T08:00:00+03:00"))
    }

    @Test func backupIsACompleteSingleFileCopy() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let live = try store("live.sqlite")
        try live.add(start: at("2026-10-01T09:00:00+03:00"), end: at("2026-10-01T17:00:00+03:00"), now: at("2026-10-26T12:00:00+02:00"))
        try live.add(start: at("2026-10-02T09:00:00+03:00"), end: at("2026-10-02T17:00:00+03:00"), now: at("2026-10-26T12:00:00+02:00"))
        try live.setDayOverride(DayOverride(date: day("2026-10-05"), kind: .vacation), now: at("2026-10-26T12:00:00+02:00"))

        let backupURL = folder.appendingPathComponent("backup.sqlite")
        try live.backup(to: backupURL)
        #expect(!FileManager.default.fileExists(atPath: backupURL.path + "-wal"))

        let summary = try SessionStore.inspectBackup(at: backupURL)
        #expect(summary.sessionCount == 2)
        #expect(summary.firstSession == at("2026-10-01T09:00:00+03:00"))
        #expect(summary.lastSession == at("2026-10-02T09:00:00+03:00"))

        let copy = try SessionStore(url: backupURL)
        #expect(try copy.allSessions().count == 2)
        #expect(try copy.dayOverrides().count == 1)
    }

    @Test func restoreReplacesDataAndKeepsASafetyCopy() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = try store("old.sqlite")
        try old.add(start: at("2026-09-01T09:00:00+03:00"), end: at("2026-09-01T17:00:00+03:00"), now: at("2026-10-26T12:00:00+02:00"))
        let backupURL = folder.appendingPathComponent("old-backup.sqlite")
        try old.backup(to: backupURL)

        let live = try store("live.sqlite")
        try live.add(start: at("2026-10-20T09:00:00+03:00"), end: at("2026-10-20T12:00:00+03:00"), now: at("2026-10-26T12:00:00+02:00"))
        try live.add(start: at("2026-10-21T09:00:00+03:00"), end: at("2026-10-21T12:00:00+03:00"), now: at("2026-10-26T12:00:00+02:00"))

        let safety = folder.appendingPathComponent("Backups/before-restore.sqlite")
        try live.restore(from: backupURL, safetyCopy: safety)

        #expect(try live.allSessions().map(\.start) == [at("2026-09-01T09:00:00+03:00")])
        #expect(try SessionStore.inspectBackup(at: safety).sessionCount == 2)
        // The live store keeps working after a restore.
        try live.start(at: at("2026-10-26T09:00:00+02:00"), now: at("2026-10-26T09:00:00+02:00"))
        #expect(try live.openSession() != nil)
    }

    @Test func rejectsFilesThatAreNotOlekBackups() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let text = folder.appendingPathComponent("notes.sqlite")
        try Data("just some text, definitely not SQLite".utf8).write(to: text)
        #expect(throws: BackupError.notADatabase) { try SessionStore.inspectBackup(at: text) }

        let other = folder.appendingPathComponent("other.sqlite")
        try Database(path: other.path).execute("CREATE TABLE something (id INTEGER)")
        #expect(throws: BackupError.notAnOlekBackup) { try SessionStore.inspectBackup(at: other) }

        let newer = folder.appendingPathComponent("newer.sqlite")
        _ = try SessionStore(url: newer)
        try Database(path: newer.path).execute("PRAGMA user_version = \(Migrations.latestVersion + 1)")
        #expect(throws: BackupError.newerVersion(Migrations.latestVersion + 1)) { try SessionStore.inspectBackup(at: newer) }
    }

    @Test func rejectedRestoreLeavesDataUntouched() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let live = try store("live.sqlite")
        try live.add(start: at("2026-10-20T09:00:00+03:00"), end: at("2026-10-20T12:00:00+03:00"), now: at("2026-10-26T12:00:00+02:00"))
        let junk = folder.appendingPathComponent("junk.sqlite")
        try Data(repeating: 7, count: 8192).write(to: junk)
        #expect(throws: BackupError.self) {
            try live.restore(from: junk, safetyCopy: folder.appendingPathComponent("safety.sqlite"))
        }
        #expect(try live.allSessions().count == 1)
    }

    @Test func generalSettingsPersist() throws {
        let store = try SessionStore.inMemory()
        #expect(try store.generalSettings().menuBarText == .sessionWhileWorking)
        try store.saveGeneralSettings(GeneralSettings(menuBarText: .todayTotal))
        #expect(try store.generalSettings().menuBarText == .todayTotal)
    }
}
