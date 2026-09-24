import Testing
import AppKit
import ApolloConfig
import ApolloRuntime
import ApolloProviders
@testable import ApolloShell

@MainActor
@Suite("Marketplace: Spalten folgen der Fensterbreite, mindestens 220 pt je Karte (11-9, MP-04)")
struct MarketplaceColumnsTests {
    static func grid(_ elements: [ElementInstance]) -> ElementInstance? {
        for element in elements {
            if element.kind == "grid" { return element }
            if let found = grid(element.children) { return found }
        }
        return nil
    }

    @Test("780 pt: 3 Spalten, 640 pt: 2, 1100 pt: 4")
    func adaptive() throws {
        let resources = PackageResources.root.appendingPathComponent("Resources")
        let builtin = resources.appendingPathComponent("builtin")
        let session = try RenderSession(config: builtin, resources: resources, fixture: ProviderFixture.load(builtin.appendingPathComponent("fixture.kdl")),
                                        fixtureRoot: builtin, dark: false, scale: 1)
        let runtime = session.assembly.runtime
        let surface = try #require(session.surface("marketplace"))
        runtime.open("marketplace", screenKey: nil)
        session.flush()
        func columns(_ width: Double?) throws -> String? {
            if let width { runtime.setSurfaceSize("marketplace", screenKey: surface.screenKey, width: width, height: 620) }
            session.flush()
            return try #require(Self.grid(surface.root)).property("style").plainText
        }
        #expect(try columns(nil)?.contains("repeat(3, 1fr)") == true)
        #expect(try columns(640)?.contains("repeat(2, 1fr)") == true)
        #expect(try columns(1100)?.contains("repeat(4, 1fr)") == true)
        #expect(try columns(780)?.contains("repeat(3, 1fr)") == true)
    }
}
