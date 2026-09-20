import Foundation

/// Where this installation came from. How an update is installed hangs on it.
/// eingespielt wird.
/// - `.disk`: out of the DMG (or a build of one's own). The app may renew
///   itself, and Sparkle takes care of that.
///
/// - `.homebrew`: from `brew install`. The app lies in the Cellar and belongs
///   to Homebrew. If it replaced itself there, Homebrew's inventory would no
///   longer be right, and the next `brew upgrade` would undo it. So the app
///   only reports new versions and names the command.
///
///
/// That is not recognised by the path - it can lie anywhere, and symlinks make
/// guessing by path unreliable (see `~/Applications/ApolloShell.app` as a link
/// into the Cellar) - but by a marker file the formula puts into the bundle
/// while building.
public enum InstallKind: String, Equatable, Hashable, Sendable, CaseIterable {
    case disk
    case homebrew

    /// The name of the marker file in `Contents/Resources`. Its content does
    /// not matter; that it is there is enough.
    public static let markerName = "installed-by-homebrew"

    /// The command that updates a Homebrew installation.
    public static let homebrewUpgradeCommand = "brew upgrade apolloshell"

    /// Decides by the bundle. `resourcesURL` is `Bundle.main.resourceURL`;
    /// without a bundle (`swift run`, say) `.disk` holds.
    public static func detect(resourcesURL: URL?,
                              fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> InstallKind {
        guard let resourcesURL else { return .disk }
        return fileExists(resourcesURL.appendingPathComponent(markerName)) ? .homebrew : .disk
    }

    /// May this installation renew itself?
    public var updatesItself: Bool { self == .disk }
}
