import Testing
import AppKit
import SwiftUI
import ApolloConfig
@testable import ApolloShell

@MainActor
@Suite("Platzierung: area=full und offset")
struct PlacementFindingTests {
    func spec(_ kind: String, _ values: [String: Value] = [:]) -> SurfaceWindowSpec {
        SurfaceWindowSpec(kind: kind, property: { values[$0] ?? .null })
    }

    @Test("area=full lässt AppKit den Rahmen nicht unter die Menüleiste schieben")
    func fullArea() throws {
        let w = AppKitHostWindow(spec: spec("panel", ["area": .string("full"), "anchor": .string("top")]), content: AnyView(EmptyView()))
        let p = try #require(w.window as? ShellPanel)
        #expect(p.mayLeaveScreen)
        let r = CGRect(x: 0, y: 870, width: 1440, height: 30)
        #expect(p.constrainFrameRect(r, to: nil) == r)
        let below = AppKitHostWindow(spec: spec("panel"), content: AnyView(EmptyView()))
        #expect((below.window as? ShellPanel)?.mayLeaveScreen == false)
    }

    @Test("Schattenraum erlaubt den Rahmen ausserhalb des Bildschirms")
    func bleed() throws {
        let w = AppKitHostWindow(spec: spec("panel"), content: AnyView(EmptyView()))
        w.setBleed(EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0))
        #expect((w.window as? ShellPanel)?.mayLeaveScreen == true)
    }

    @Test("offset-y bei anchor=left zählt von der Mitte, bei top-left von oben")
    func offset() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let left = SurfacePlacement(anchor: .left, area: .full, offsetY: 10).frame(screen: screen, visible: screen, fitting: CGSize(width: 100, height: 200))
        #expect(left.minY == 290)
        let top = SurfacePlacement(anchor: .topLeft, area: .full, offsetY: 10).frame(screen: screen, visible: screen, fitting: CGSize(width: 100, height: 200))
        #expect(top.maxY == 790)
    }
}
