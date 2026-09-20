import Foundation

/// Where ApolloShell puts its files, in one place:
/// ~/Library/Application Support/ApolloShell/. Until now every file worked the
/// folder out itself, partly through another one (`PinnedApps.url` out of
/// `UsageStore.defaultURL`).
///
/// The names are part of the format: existing installations read exactly these
/// files, and a test pins them down. Never rename them.
public struct ShellFiles: Sendable {
    /// The folder all the files lie in.
    public let directory: URL

    /// A folder of one's own, for image samples and tests, say.
    public init(directory: URL) {
        self.directory = directory
    }

    /// The name of the folder under Application Support.
    public static let folderName = "ApolloShell"

    /// The real folder of the logged-in user.
    public static var live: ShellFiles {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ShellFiles(directory: support.appendingPathComponent(folderName, isDirectory: true))
    }

    /// The settings (Nexus), see `ShellSettings`.
    public var settings: URL { file("settings.json") }
    /// The pinned apps of the launcher.
    public var pinned: URL { file("pinned.json") }
    /// The usage statistics for the order in the launcher.
    public var usage: URL { file("usage.json") }
    /// The weather places and favourites.
    public var weather: URL { file("weather.json") }
    /// The saved values of Apple's Dock while it is hidden.
    public var appleDock: URL { file("apple-dock.json") }
    /// The marker: ApolloShell switched sleep with the lid closed off and has
    /// to switch it back on.
    public var lidAwakeMarker: URL { file("lid-awake") }
    /// The folder with the themes, see `ThemeLoader`.
    public var themes: URL { ThemeLoader.folder(inApplicationSupport: directory) }

    private func file(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }
}

// MARK: - Reading and writing

/// Writing without half files. It was called `NexusFile`, but it writes for
/// the launcher and the weather too.
public extension ShellFiles {
    /// `.atomic`: into a neighbouring file first, then rename. The launcher and
    /// the weather read their file on every opening - they see the old one or
    /// the new one, never a half-written one.
    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func read(_ url: URL?) -> Data? {
        url.flatMap { try? Data(contentsOf: $0) }
    }

    /// Copy a file that could not be read next to the original
    /// (`<name>.unreadable`) before the next save replaces it. Whoever edited
    /// it broken by hand loses nothing that way.
    static func preserveUnreadable(_ url: URL) {
        let copy = url.appendingPathExtension("unreadable")
        try? FileManager.default.removeItem(at: copy)
        try? FileManager.default.copyItem(at: url, to: copy)
    }

    /// Is this a JSON object at all? Single wrong values are read leniently by
    /// ShellSettings; this is about a file that is broken entirely.
    static func isJSONObject(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
    }
}
