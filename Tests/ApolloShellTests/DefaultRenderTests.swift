import Testing
import AppKit
import ApolloBase
import ApolloProviders
@testable import ApolloShell

@MainActor
@Suite("Default-Config gezeichnet wie 0.1.4.2 (9b Paket 2)")
struct DefaultRenderTests {
    static let resources = PackageResources.root.appendingPathComponent("Resources")

    static func shot(_ id: String, state: String? = nil, theme: String? = nil) throws -> Snapshot {
        let config = state.map { resources.appendingPathComponent("render/\($0)") } ?? resources.appendingPathComponent("configs/apolloshell-default")
        let fixture = state.map { resources.appendingPathComponent("render/\($0)/fixture.kdl") }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? resources.appendingPathComponent("render/fixture.kdl")
        let session = try RenderSession(config: config, resources: resources, fixture: ProviderFixture.load(fixture),
                                        fixtureRoot: fixture.deletingLastPathComponent(), dark: false, scale: 1,
                                        theme: theme.map { PackageResources.root.appendingPathComponent("examples/themes/\($0)") })
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

    @Test("OSD stumm: Füllung nur so lang wie die Spur breit, obwohl die Lautstärke 0,35 ist", arguments: ["osd-muted", "osd-0"])
    func osdMuted(state: String) throws {
        let shot = try Self.shot("volume", state: state)
        let fill = try #require(shot.bounds { max($0.r, $0.g, $0.b) - min($0.r, $0.g, $0.b) > 120 })
        #expect(abs(fill.height - 30) <= 1.5)
    }

    @Test("Sitzungsmenü: 102 × 496, Kacheln 80 × 80 links bündig, Emblem in der Mitte am Beginn der Begrüssung")
    func session() throws {
        let shot = try Self.shot("session")
        #expect(abs(shot.size.width - 102) <= 1 && abs(shot.size.height - 496) <= 1)
        let emblem = try #require(shot.bounds { max($0.r, $0.g, $0.b) - min($0.r, $0.g, $0.b) > 120 })
        #expect(emblem.minY > 208 && emblem.maxY < 288)
        #expect(emblem.width < 60)
    }
}
