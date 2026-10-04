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

    @Test("margin-top im Stylesheet und im style-Attribut erreicht den Platzierungsrand")
    func placementMarginLonghands() throws {
        let (sheet, _) = try RenderProbe.session("panel \"t\" anchor=\"left\" { stack class=\"x\" }", css: "panel { margin: 1px; margin-top: 30px; }")
        let a = try #require(sheet.surfaces.first)
        let sa = SurfacePlacement(property: a.property, style: sheet.context.styles.resolve(surface: a)).margin
        #expect(sa.top == 30 && sa.leading == 1 && sa.bottom == 1)
        let (inline, _) = try RenderProbe.session("panel \"t\" anchor=\"left\" style=\"margin-top: 44px; margin-left: 7px\" { stack class=\"x\" }", css: "")
        let b = try #require(inline.surfaces.first)
        let sb = SurfacePlacement(property: b.property, style: inline.context.styles.resolve(surface: b)).margin
        #expect(sb.top == 44 && sb.leading == 7 && sb.trailing == 0)
    }
}
