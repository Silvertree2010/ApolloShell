import Testing
import Foundation
import ApolloConfig
import ApolloProviders
@testable import ApolloShell

@MainActor
@Suite("Kontextwurzel theme")
struct ThemeRootTests {
    @Test("theme.set nennt die Tokens des Themes ohne --apollo-, ohne Theme bleibt set leer")
    func themeSet() throws {
        let config = try RenderProbe.folder(["shell.kdl": Data("panel \"p\" anchor=\"left\" { text \"x\" }\n".utf8),
                                             "red.css": Data(":root { --apollo-theme-name: \"Red\"; --apollo-bar-color: #ff0000; }\n".utf8)])
        let fixture = ProviderFixture.load(PackageResources.root.appendingPathComponent("Resources/render/fixture.kdl"))
        let resources = PackageResources.root.appendingPathComponent("Resources")
        let themed = try RenderSession(config: config, resources: resources, fixture: fixture, fixtureRoot: config, dark: false, scale: 1,
                                       theme: config.appendingPathComponent("red.css"))
        #expect(themed.assembly.store.value(DependencyPath("theme", ["set", "bar-color"])) == .bool(true))
        #expect(themed.assembly.store.value(DependencyPath("theme", ["name"])) == .string("Red"))
        #expect(themed.assembly.store.value(DependencyPath("theme", ["dark"])) == .bool(false))
        let plain = try RenderSession(config: config, resources: resources, fixture: fixture, fixtureRoot: config, dark: true, scale: 1)
        #expect(plain.assembly.store.value(DependencyPath("theme", ["set", "bar-color"])) == .null)
        #expect(plain.assembly.store.value(DependencyPath("theme", ["id"])) == .null)
        #expect(plain.assembly.store.value(DependencyPath("theme", ["appearance"])) == .string("dark"))
    }
}
