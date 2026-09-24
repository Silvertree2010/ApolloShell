import Testing
import AppKit
import SwiftUI
import ApolloBase
import ApolloRuntime
import ApolloStyle
@testable import ApolloShell

@MainActor
extension Mounted {
    var surface: SurfaceInstance? { session.surfaces.first }

    func show(_ visible: Bool) throws {
        let surface = try #require(surface)
        surface.isVisible = visible
        let hosting = try #require(view as? NSHostingView<AnyView>)
        hosting.rootView = session.root(surface, reserve: EdgeInsets())
        pump(5)
    }
}

@MainActor
@Suite("Gemountete Oberfläche: verborgen heisst nicht mehr gezeigt", .serialized)
struct ShownMountTests {
    @Test("surfaceShown auf false ruft StopWhenHidden, womit der key-recorder die Aufnahme beendet")
    func recorderStopsWhenHidden() async throws {
        let mounted = try Mounted.mount("panel \"t\" anchor=\"left\" { text \"x\" }", css: "#t { width: 40px; height: 20px; }")
        let surface = try #require(mounted.surface)
        surface.isVisible = true
        var stops = 0
        let hosting = try #require(mounted.view as? NSHostingView<AnyView>)
        func mount() {
            hosting.rootView = AnyView(Color.clear.frame(width: 10, height: 10).modifier(StopWhenHidden { stops += 1 }).environment(\.surfaceShown, surface.isVisible))
            mounted.pump(5)
        }
        mount()
        #expect(stops == 0)
        surface.isVisible = false
        mount()
        #expect(stops == 1)
        surface.isVisible = true
        mount()
        #expect(stops == 1)
    }

    @Test("SurfaceView reicht die Sichtbarkeit der Oberfläche als surfaceShown an ihren Inhalt weiter")
    func surfaceViewPassesShown() throws {
        let (session, _) = try RenderProbe.session("panel \"t\" anchor=\"left\" { text \"x\" }", css: "#t { width: 40px; height: 20px; }")
        let surface = try #require(session.surfaces.first)
        let probe = ShownProbe()
        let hosting = NSHostingView(rootView: AnyView(EmptyView()))
        for visible in [false, true, false] {
            surface.isVisible = visible
            hosting.rootView = AnyView(SurfaceView(surface: surface, context: session.context, painter: probe))
            hosting.frame = CGRect(x: 0, y: 0, width: 40, height: 20)
            hosting.layoutSubtreeIfNeeded()
            RunLoopPump.run(0.05)
        }
        #expect(probe.seen == [false, true, false])
    }

    @Test("Gemountete Oberfläche meldet Element-Rahmen mit id, ohne sie von Hand einzuspeisen")
    func elementFramesFromMount() throws {
        let mounted = try Mounted.mount("panel \"bar\" anchor=\"left\" { row { text \"a\" id=\"clock\" } }",
                                        css: "#bar { width: 120px; height: 30px; align-items: start; } #clock { width: 40px; height: 20px; }")
        let surface = try #require(mounted.surface)
        mounted.pump(5)
        let frame = try #require(mounted.session.context.elementFrames.frame("clock", surfaceKey: SurfaceHost.key(surface.id, surface.screenKey)))
        #expect(frame.size == CGSize(width: 40, height: 20))
    }
}

@MainActor
final class ShownProbe: BackgroundPainter {
    var seen: [Bool] = []

    func background(for surface: SurfaceInstance, style: ComputedStyle) -> BackgroundChoice {
        .replaced(AnyView(ShownProbeView(probe: self)))
    }
}

struct ShownProbeView: View {
    let probe: ShownProbe
    @Environment(\.surfaceShown) private var shown

    var body: some View {
        Color.clear.onAppear { probe.seen.append(shown) }.onChange(of: shown) { _, value in probe.seen.append(value) }
    }
}
