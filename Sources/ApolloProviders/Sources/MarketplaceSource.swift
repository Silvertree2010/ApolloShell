import Foundation
import ApolloShellCore

@MainActor
public protocol MarketplaceHost: AnyObject {
    var baseURL: URL { get }
    var installer: MarketThemeInstaller { get }
    var activeTheme: String? { get }
    func loadSession() -> String?
    func saveSession(_ session: String)
    func deleteSession()
    func open(_ url: URL)
    func copy(_ text: String)
    func localThemes() -> [Theme]
    func selectTheme(_ id: String?) throws
    func themesChanged(identifier: String?)
}
