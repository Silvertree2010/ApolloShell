import Foundation

public enum Uninstall {
    public static let tccutil = "/usr/bin/tccutil"
    public static let brewCommand = "brew uninstall apolloshell"
    public static let defaults = "/usr/bin/defaults"

    public static func defaultsArguments(id: String = AppIdentity.bundleID) -> [String] {
        ["delete", id]
    }

    public static func tccArguments(id: String = AppIdentity.bundleID) -> [String] {
        ["reset", "All", id]
    }

    public static func paths(home: URL, id: String = AppIdentity.bundleID) -> [URL] {
        let l = home.appending(path: "Library", directoryHint: .isDirectory)
        return [
            "Application Support/\(ShellFiles.folderName)",
            "Caches/\(id)",
            "HTTPStorages/\(id)",
            "HTTPStorages/\(id).binarycookies",
            "WebKit/\(id)",
            "Saved Application State/\(id).savedState",
            "Preferences/\(id).plist",
        ].map { l.appending(path: $0) }
    }
}
