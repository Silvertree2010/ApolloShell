import AppKit
import ApolloConfig
import ApolloControl
import ApolloProviders
import ApolloRuntime
import ApolloShellCore

@MainActor
final class SystemMarketplaceHost: MarketplaceHost {
    static let urlDefaultsKey = "MarketplaceURL"

    let paths: ConfigPaths
    let settings: SettingsStore
    let installer: MarketThemeInstaller
    var onThemesChanged: (@MainActor () -> Void)?

    init(paths: ConfigPaths, settings: SettingsStore) {
        self.paths = paths
        self.settings = settings
        installer = MarketThemeInstaller(
            themes: paths.themesDirectory,
            legacyThemes: paths.legacyThemesDirectory,
            indexFile: paths.applicationSupport.appendingPathComponent("marketplace.json")
        )
    }

    static func baseURL(_ defaults: UserDefaults = .standard) -> URL {
        defaults.string(forKey: urlDefaultsKey).flatMap(URL.init(string:)) ?? MarketplaceClient.productionURL
    }

    var baseURL: URL { Self.baseURL() }

    var activeTheme: String? { settings.settings.theme }

    func loadSession() -> String? { MarketplaceKeychain.load() }
    func saveSession(_ session: String) { MarketplaceKeychain.save(session) }
    func deleteSession() { MarketplaceKeychain.delete() }
    func open(_ url: URL) { NSWorkspace.shared.open(url) }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func localThemes() -> [Theme] {
        var seen: Set<String> = []
        var result: [Theme] = []
        for folder in [paths.themesDirectory, paths.legacyThemesDirectory] {
            for theme in ThemeLoader.themes(in: folder) where seen.insert(theme.identifier).inserted {
                result.append(theme)
            }
        }
        return result.sorted { $0.identifier.localizedStandardCompare($1.identifier) == .orderedAscending }
    }

    func selectTheme(_ id: String?) throws {
        try ThemeCatalog(paths: paths, settings: settings).select(id)
        onThemesChanged?()
    }

    func themesChanged(identifier: String?) {
        guard let identifier, identifier == activeTheme else { return }
        onThemesChanged?()
    }
}

@MainActor
final class MarketplaceOpenAction: ActionImplementation {
    weak var shell: LiveShell?

    init(shell: LiveShell) {
        self.shell = shell
    }

    func perform(_ call: ResolvedActionCall, environment: ActionEnvironment, runtime: any ActionRuntime) async throws {
        shell?.openMarketplace()
    }
}
