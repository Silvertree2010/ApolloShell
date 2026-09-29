import Testing
import AppKit
import ApolloBase
import ApolloConfig
import ApolloProviders
import ApolloRuntime
@testable import ApolloShell

@MainActor
@Suite("Layout-Arbeit des offenen Dashboards")
struct LayoutWorkTests {
    static let resources = PackageResources.root.appendingPathComponent("Resources")

    static func mounted(_ id: String) throws -> (RenderSession, NSView) {
        let fixture = resources.appendingPathComponent("render/fixture.kdl")
        let session = try RenderSession(config: resources.appendingPathComponent("configs/apolloshell-default"), resources: resources,
                                        fixture: ProviderFixture.load(fixture), fixtureRoot: fixture.deletingLastPathComponent(), dark: true, scale: 1)
        let surface = try #require(session.surface(id))
        session.assembly.runtime.open(surface.id, screenKey: surface.screenKey)
        session.assembly.runtime.surfaceDidFinishOpening(id: surface.id, screenKey: surface.screenKey)
        session.flush()
        let view = session.mount(surface)
        for _ in 0..<10 { session.canvas.settle() }
        return (session, view)
    }

    static func measures(_ work: () -> Void) -> Int {
        let before = LayoutCounter.measures.load(ordering: .relaxed)
        work()
        return LayoutCounter.measures.load(ordering: .relaxed) - before
    }

    @Test("ohne Änderung kein Layout-Durchlauf")
    func idleNoLayout() throws {
        let (session, _) = try Self.mounted("dashboard")
        let count = Self.measures { for _ in 0..<10 { session.canvas.settle() } }
        #expect(count == 0)
    }

    @Test("CPU-Wert ändern misst jedes Layout höchstens wenige Male, nicht exponentiell über die Tiefe")
    func cpuChange() throws {
        let (session, _) = try Self.mounted("dashboard")
        var counts: [Int] = []
        for value in [0.1, 0.2, 0.3] {
            counts.append(Self.measures {
                session.assembly.store.set(DependencyPath("perf", ["cpu"]), .number(value))
                session.flush()
                for _ in 0..<5 { session.canvas.settle() }
            })
        }
        #expect(counts.allSatisfy { $0 < 800 }, "\(counts)")
    }
}
