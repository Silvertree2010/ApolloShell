import Foundation
import ApolloConfig
import ApolloShellCore

public struct ThemeEntry: Sendable, Hashable {
    public var id: String
    public var title: String
    public var issueCount: Int
    public var isLegacyLocation: Bool
    public var isActive: Bool
}

public struct ThemeCatalog: Sendable {
    public let paths: ConfigPaths
    public let settings: SettingsStore

    public init(paths: ConfigPaths, settings: SettingsStore) {
        self.paths = paths
        self.settings = settings
    }

    public func list() -> [ThemeEntry] {
        let active = settings.settings.theme
        var seen: Set<String> = []
        var entries: [ThemeEntry] = []
        for (folder, legacy) in [(paths.themesDirectory, false), (paths.legacyThemesDirectory, true)] {
            for theme in ThemeLoader.themes(in: folder) where !seen.contains(theme.identifier) {
                seen.insert(theme.identifier)
                entries.append(ThemeEntry(id: theme.identifier, title: theme.title, issueCount: theme.issues.count, isLegacyLocation: legacy, isActive: theme.identifier == active))
            }
        }
        return entries.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    public func select(_ id: String?) throws {
        if let id, !list().contains(where: { $0.id == id }) {
            throw ShellControlError("no theme named '\(id)'")
        }
        try settings.apply(.theme(id))
    }
}
