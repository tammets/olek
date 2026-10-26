import Foundation

enum AppPaths {
    /// Debug builds use a separate folder so development never touches real tracking data.
    static var dataFolder: URL {
        #if DEBUG
        let folder = "Olek Dev"
        #else
        let folder = "Olek"
        #endif
        return URL.applicationSupportDirectory.appending(path: folder, directoryHint: .isDirectory)
    }

    static var databaseURL: URL {
        dataFolder.appending(path: "olek.sqlite")
    }

    /// Safety copies made before a restore.
    static var backupsFolder: URL {
        dataFolder.appending(path: "Backups", directoryHint: .isDirectory)
    }
}
