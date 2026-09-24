import Foundation

public enum InstallKind: String, Equatable, Hashable, Sendable, CaseIterable {
    case disk
    case homebrew

    public static let markerName = "installed-by-homebrew"

    public static let homebrewUpgradeCommand = "brew upgrade apolloshell"

    public static func detect(resourcesURL: URL?,
                              fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> InstallKind {
        guard let resourcesURL else { return .disk }
        return fileExists(resourcesURL.appendingPathComponent(markerName)) ? .homebrew : .disk
    }

    public var updatesItself: Bool { self == .disk }
}
