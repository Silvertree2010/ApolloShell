import Testing
import AppKit
import ApolloBase
import ApolloProviders
@testable import ApolloShell

@MainActor
@Suite("Default-Config gezeichnet wie 0.1.4.2 (9b Paket 2)")
struct DefaultRenderTests {
    static let resources = PackageResources.root.appendingPathComponent("Resources")

    static func shot(_ id: String) throws -> Snapshot {
        let session = try RenderSession(config: resources.appendingPathComponent("configs/apolloshell-default"), resources: resources,
                                        fixture: ProviderFixture.load(resources.appendingPathComponent("render/fixture.kdl")),
                                        fixtureRoot: resources.appendingPathComponent("render"), dark: false, scale: 1)
        let surface = try #require(session.surface(id))
        return Snapshot(rep: try #require(NSBitmapImageRep(data: try session.capture(surface, name: id))), scale: 1)
    }

    @Test("Desktop-Uhr: Zeile mit Zeit, Strich und Datum, 24 pt Schattenraum, Schatten sichtbar auf hellem Grund")
    func desktopClock() throws {
        let shot = try Self.shot("desktop-clock")
        #expect(abs(shot.size.width - 479) <= 4)
        #expect(abs(shot.size.height - 163) <= 4)
        let shadow = try #require(shot.bounds { $0.r < 200 })
        #expect(shadow.minX < 40 && shadow.maxX > 200, "\(shadow)")
        #expect(shadow.height < 140)
    }

    @Test("OSD: Regler 30 × 150 mittig in 52 × 182, Füllung bei 0,35 bis 52,5 pt")
    func osd() throws {
        let shot = try Self.shot("volume")
        #expect(shot.size == CGSize(width: 52, height: 182))
        let fill = try #require(shot.bounds { max($0.r, $0.g, $0.b) - min($0.r, $0.g, $0.b) > 120 })
        #expect(abs(fill.minX - 11) <= 1 && abs(fill.width - 30) <= 1)
        #expect(abs(fill.height - 52.5) <= 1.5)
    }
}
