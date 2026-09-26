import CoreGraphics
import Testing
@testable import ApolloWM
@testable import ApolloWMCore

@MainActor
@Suite("TilingEngine ohne echte Fenster")
struct TilingEngineTests {
    func engine(_ ids: [CGWindowID]) -> TilingEngine {
        let engine = TilingEngine(area: CGRect(x: 0, y: 0, width: 1200, height: 800))
        engine.log = { _ in }
        var layouts = SpaceLayouts<Desk, CGWindowID>()
        for id in ids { layouts.assign(id, to: engine.desk) { $0.insert(id) } }
        engine.restore(.init(layouts: layouts, floating: [:], activeWorkspace: [:], originalFrames: [:], groups: nil), alive: { _ in true })
        return engine
    }

    @Test("Im Canvas findet window(at:) das Fenster, das dort wirklich liegt")
    func canvasHitTest() throws {
        let engine = engine([1, 2, 3])
        engine.options.layout = .canvas
        let frames = engine.frames(on: engine.desk)
        let second = try #require(frames[2])
        #expect(engine.window(at: CGPoint(x: second.midX, y: second.maxY - 5)) == 2)
        #expect(engine.window(at: CGPoint(x: second.midX, y: second.minY + 5)) == 2)
    }

    @Test("Zu grosse Abstände liefern keine unendlichen Ziele", arguments: [LayoutMode.dwindle, .canvas])
    func oversizedGaps(_ layout: LayoutMode) {
        let engine = engine([1, 2])
        engine.options.layout = layout
        engine.options.gaps = Gaps(outer: 100_000, inner: 10)
        let frames = engine.frames(on: engine.desk)
        #expect(frames.values.allSatisfy { [$0.minX, $0.minY, $0.width, $0.height].allSatisfy(\.isFinite) })
    }
}
