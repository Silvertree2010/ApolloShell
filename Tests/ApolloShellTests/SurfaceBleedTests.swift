import Testing
import AppKit
import SwiftUI
import ApolloStyle
@testable import ApolloShell

@MainActor
@Suite("Schattenraum um Flächen")
struct SurfaceBleedTests {
    @Test("box-shadow vergrössert das Fenster um Unschärfe, Ausdehnung und Versatz")
    func shadow() throws {
        let f = try HostFixture("popup \"p\" anchor=\"center\" { text \"x\" }", css: "#p { width: 300px; height: 200px; box-shadow: 0 10px 20px rgba(0,0,0,0.5); }")
        f.assembly.runtime.open("p", screenKey: HostFixture.screen.key)
        f.flush()
        let w = try #require(f.window("p"))
        #expect(w.frame == CGRect(x: 550, y: 305, width: 340, height: 240))
        #expect(f.host.controllers[SurfaceHost.key("p", HostFixture.screen.key)]?.openFrame == CGRect(x: 570, y: 335, width: 300, height: 200))
    }

    @Test("Glas bekommt Raum für seinen eigenen Schatten")
    func glass() throws {
        let f = try HostFixture("popup \"p\" anchor=\"center\" { text \"x\" }", css: "#p { width: 300px; height: 200px; background: glass(regular); }")
        f.assembly.runtime.open("p", screenKey: HostFixture.screen.key)
        f.flush()
        let w = try #require(f.window("p"))
        let g = SurfaceBleed.glass
        #expect(w.frame == CGRect(x: 570 - g, y: 335 - g, width: 300 + 2 * g, height: 200 + 2 * g))
    }

    @Test("am Bildschirmrand entfällt der Schattenraum auf dieser Seite")
    func edge() throws {
        let f = try HostFixture("panel \"p\" anchor=\"left\" { text \"x\" }", css: "#p { width: 100px; height: 200px; box-shadow: 0 0 20px black; }")
        let w = try #require(f.window("p"))
        #expect(w.frame.minX == 0)
        #expect(w.frame.width == 120)
    }

    @Test("ohne Schatten und Glas bleibt das Fenster so gross wie die Fläche")
    func none() {
        #expect(SurfaceBleed.insets(ComputedStyle(values: [:])) == EdgeInsets())
    }
}
