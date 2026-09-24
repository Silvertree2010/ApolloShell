import Testing
import AppKit
@testable import ApolloShell

@MainActor
@Suite("click-through auto: überlaufendes scroll zählt mit seinem ganzen Sichtfenster (Ruling 06c Fix-Runde 2)")
struct ScrollHitTests {
    static func regions(_ count: Int) throws -> [HitRegion] {
        let rows = (0..<count).map { "text \"row \($0)\" class=\"r\"" }.joined(separator: "\n")
        let (session, _) = try RenderProbe.session("panel \"t\" anchor=\"left\" { scroll class=\"s\" {\n\(rows)\n} }",
                                                   css: ".s { width: 120px; height: 60px; } .r { height: 20px; }")
        let surface = try #require(session.surfaces.first)
        let hosting = session.mount(surface)
        for _ in 0..<20 {
            RunLoopPump.run(0.01)
            hosting.layoutSubtreeIfNeeded()
        }
        return session.context.hits.regions(for: SurfaceHost.key(surface.id, surface.screenKey))
    }

    @Test("überlaufend: Sichtfenster ist Trefferfläche, auch in Lücken zwischen Einträgen")
    func overflowing() throws {
        let list = try Self.regions(12)
        let viewport = try #require(list.first)
        #expect(list.count == 1)
        #expect(viewport.frame.height == 60)
        #expect(viewport.frame.width == 120)
    }

    @Test("passt der Inhalt, bleibt das scroll durchlässig")
    func fitting() throws {
        #expect(try Self.regions(2).isEmpty)
    }
}
