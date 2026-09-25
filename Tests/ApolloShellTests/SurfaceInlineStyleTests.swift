import Testing
import SwiftUI
import ApolloStyle
@testable import ApolloShell

@MainActor
@Suite("style= an Oberflächen wirkt (W4, blocks.md 1)")
struct SurfaceInlineStyleTests {
    @Test("Inline-Stil am panel setzt Breite über dem Stylesheet")
    func panelInlineStyle() throws {
        let (session, _) = try RenderProbe.session("panel \"t\" anchor=\"left\" style=\"width: 80px\" { stack class=\"x\" }", css: "panel { width: 24px; }")
        let surface = try #require(session.surfaces.first)
        let style = session.context.styles.resolve(surface: surface)
        #expect(SurfacePlacement(property: surface.property, style: style).width == CSSLength(80, .points))
    }
}
