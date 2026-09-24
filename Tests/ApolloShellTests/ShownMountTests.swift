import Testing
import AppKit
import SwiftUI
import ApolloBase
import ApolloRuntime
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
}
