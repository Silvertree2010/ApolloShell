import Testing
import AppKit
import SwiftUI
@testable import ApolloShell

@MainActor
@Suite("Oberflächen-margin wirkt nur einmal: als Abstand der Fläche, nicht zusätzlich als Polsterung")
struct SurfaceMarginTests {
    @Test("Panel mit margin: Bild so gross wie der Inhalt, der Rand rückt nur das Fenster ab")
    func marginOnce() throws {
        let kdl = "panel \"p\" anchor=\"bottom-right\" area=\"visible\" { stack class=\"box\" }"
        let css = ".box { width: 100px; height: 50px; background: rgb(255 0 0); } #p { margin: 16px; }"
        let shot = try RenderProbe.render(kdl, css: css)
        #expect(shot.size == CGSize(width: 100, height: 50), "\(shot.size)")
    }

    @Test("overhang mit fester Höhe: der Überhang kommt zur Höhe dazu, sichtbar bleibt die volle CSS-Höhe")
    func overhangKeepsHeight() throws {
        let (session, _) = try RenderProbe.session("popup \"p\" anchor=\"bottom\" overhang=#true { stack class=\"box\" }",
                                                   css: "#p { height: 100px; border-radius: 20px; } .box { width: 50px; height: 10px; }")
        let surface = try #require(session.surfaces.first)
        let view = NSHostingView(rootView: SurfaceView(surface: surface, context: session.context, insets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0)))
        #expect(abs(view.fittingSize.height - 120) < 0.5, "\(view.fittingSize)")
    }
}

