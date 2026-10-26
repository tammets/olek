import Foundation

enum AppPaths {
    /// Debug builds use a separate folder so development never touches real tracking data.
    static var databaseURL: URL {
        #if DEBUG
        let folder = "Olek Dev"
        #else
        let folder = "Olek"
        #endif
        return URL.applicationSupportDirectory
            .appending(path: folder, directoryHint: .isDirectory)
            .appending(path: "olek.sqlite")
    }
}
