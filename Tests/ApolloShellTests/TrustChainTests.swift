import Testing
import Foundation
import ApolloBase
import ApolloConfig
import ApolloProviders
import ApolloShellCore
@testable import ApolloShell

@MainActor
@Suite("Vertrauenskette: Marketplace-Theme bis KDL", .serialized)
struct TrustChainTests {
    @Test("Ein Marketplace-Theme mit Aktions- und Ausdruckssyntax bleibt Text und löst nichts aus")
    func marketplaceThemeStaysData() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("trust-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let marker = base.appendingPathComponent("pwned")
        let payload = "x{exec \\\"touch \(marker.path)\\\"} } exec \\\"touch \(marker.path)\\\" { y"
        let css = ":root {\n  --apollo-theme-name: \"\(payload)\";\n  --apollo-accent-color: #ff0000;\n}\n"
        let theme = MarketTheme(id: "evil-1", slug: "evil", name: payload, description: payload, author: payload,
                                license: "MIT", attribution: "", version: 1, updatedAt: "2026-09-25", css: css)
        let installer = MarketThemeInstaller(themes: base.appendingPathComponent("themes"), legacyThemes: base.appendingPathComponent("legacy"),
                                             indexFile: base.appendingPathComponent("marketplace.json"))
        let id = try installer.install(theme)
        let files = try FileManager.default.contentsOfDirectory(atPath: base.appendingPathComponent("themes").path)
        #expect(files == ["evil.css"])

        let config = try RenderProbe.folder([
            "shell.kdl": Data("panel \"p\" anchor=\"left\" {\n    text \"{theme.name}\"\n}\n".utf8),
        ])
        let fixture = ProviderFixture.load(PackageResources.root.appendingPathComponent("Resources/render/fixture.kdl"))
        let session = try RenderSession(config: config, resources: PackageResources.root.appendingPathComponent("Resources"), fixture: fixture,
                                        fixtureRoot: config, dark: false, scale: 1,
                                        theme: base.appendingPathComponent("themes").appendingPathComponent(id + ".css"))
        let surface = try #require(session.surfaces.first)
        _ = try session.capture(surface, name: "p")
        let text = surface.root.first?.arguments.first?.value
        guard case .string(let shown)? = text else {
            Issue.record("no text")
            return
        }
        #expect(shown.contains("exec"))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(!session.actionLog.entries.contains { $0.contains("exec") })
    }

    @Test("theme.* ist in Aktionen ein Ladefehler, Theme-Daten erreichen exec-Argumente nicht")
    func themeRootRejectedInActions() {
        let root = URL(fileURLWithPath: "/t")
        let fileSystem = MemoryFileSystem(["/t/shell.kdl": "panel \"p\" anchor=\"left\" {\n    button { on-click { exec \"echo {theme.name}\" } }\n}\n"])
        let loader = ConfigLoader(fileSystem: fileSystem, paths: ConfigPaths(builtinConfigs: root, userConfig: root, applicationSupport: root),
                                  registry: .builtin, filters: .builtin, shellVersion: ShellVersion.current)
        let result = loader.load(ConfigLocation(id: "t", root: root, isBuiltin: false))
        #expect(result.ir == nil)
        #expect(result.diagnostics.contains { $0.message == "'theme' is not valid here" })
    }
}
