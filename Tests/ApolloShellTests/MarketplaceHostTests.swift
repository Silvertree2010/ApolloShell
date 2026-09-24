import Foundation
import Security
import Testing
import ApolloBase
import ApolloConfig
import ApolloStyle
@testable import ApolloShell
import ApolloShellCore

@MainActor
@Suite("Marketplace-Host der App")
struct MarketplaceHostTests {
    @Test("MarketplaceURL aus den Defaults ersetzt die Produktions-URL (MP-22)")
    func developerURL() throws {
        let name = "marketplace-host-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(SystemMarketplaceHost.baseURL(defaults) == MarketplaceClient.productionURL)
        defaults.set("http://127.0.0.1:8788", forKey: "MarketplaceURL")
        #expect(SystemMarketplaceHost.baseURL(defaults) == URL(string: "http://127.0.0.1:8788"))
    }

    @Test("Keychain: Service <bundleID>.marketplace, Account session, erst nach dem ersten Entsperren lesbar (MP-14)")
    func keychainItem() {
        let item = MarketplaceKeychain.item("s3cret")
        #expect(item[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(item[kSecAttrService as String] as? String == AppIdentity.bundleID + ".marketplace")
        #expect(item[kSecAttrAccount as String] as? String == "session")
        #expect(item[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlock as String)
        #expect(item[kSecValueData as String] as? Data == Data("s3cret".utf8))
    }

    static let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")

    static func windowSize(css: String) throws -> [String: CGFloat?] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("market-size-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "style \"style.css\"\n".write(to: folder.appendingPathComponent("shell.kdl"), atomically: true, encoding: .utf8)
        try css.write(to: folder.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)
        let paths = ConfigPaths(builtinConfigs: resources.appendingPathComponent("configs"), userConfig: folder, applicationSupport: folder)
        let loader = ConfigLoader(fileSystem: DiskFileSystem(), paths: paths, registry: .builtin, filters: .builtin, shellVersion: ShellVersion.current)
        let merged = BuiltinSurfaces.apply(loader.load(ConfigLocation(id: "mine", root: folder, isBuiltin: false))) {
            BuiltinSurfaces.load(paths: paths, fileSystem: DiskFileSystem(), shellVersion: ShellVersion.current)
        }
        let ir = try #require(merged.ir)
        let styles = StyleResolver(sheets: StyleSheets.load(ir).0, environment: StyleSheets.environment(dark: false))
        let style = styles.resolve(StyleSubject(kind: "window", id: "marketplace"), ancestors: [], parent: nil)
        return Dictionary(uniqueKeysWithValues: ["width", "height", "min-width", "min-height"].map { ($0, StyleValues.points(style[$0])) })
    }

    @Test("Fenstergrösse aus dem aufgelösten Stil: 780×620, min 640×480, #marketplace der Config gewinnt (MP-01)")
    func windowSize() throws {
        #expect(try Self.windowSize(css: "") == ["width": 780, "height": 620, "min-width": 640, "min-height": 480])
        #expect(try Self.windowSize(css: "#marketplace { width: 900px; min-height: 500px; }\n") == ["width": 900, "height": 620, "min-width": 640, "min-height": 500])
    }
}
