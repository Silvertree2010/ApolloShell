import Testing
import ApolloStyle
@testable import ApolloShell

@MainActor
@Suite("Reload-Falle R4b: dynamische Slots je Element statt je Sheet")
struct ReloadBranchTests {
    @Test("Regeln für andere Elemente schalten die Zweige eines Elements nicht um")
    func perElement() throws {
        let (session, _) = try RenderProbe.session("""
        panel "t" anchor="left" {
            stack class="a"
            stack class="b"
            stack class="c"
        }
        """, css: ".a { animation: spin 1s infinite; filter: blur(2px); } .b:hover { opacity: 0.5; } .c { opacity: 1; }")
        let styles = session.context.styles
        let elements = try #require(session.surfaces.first).root
        func subject(_ index: Int) -> StaticSubject { StyleResolver.staticSubject(for: elements[index]) }
        #expect(styles.declares("animation", subject(0)))
        #expect(styles.declares("filter", subject(0)))
        #expect(!styles.declares("animation", subject(2)))
        #expect(!styles.declares("filter", subject(2)))
        #expect(styles.stateStyled(.hover, subject(1)))
        #expect(!ElementView.needsInteraction(elements[2], styles: styles, reorder: false))
        #expect(ElementView.needsInteraction(elements[1], styles: styles, reorder: false, stateStyled: true))
    }

    @Test("Klassen aus Ausdrücken zählen mit allen Kandidaten, unbekannte Ausdrücke passen auf jede Klasse")
    func expressionClasses() throws {
        let (session, _) = try RenderProbe.session("""
        var on #false
        var name "x"
        panel "t" anchor="left" {
            stack class="tile {var.on ? 'lit' : ''}"
            stack class="tile {var.name}"
            stack class="tile x{var.on ? 'a' : 'b'}"
            stack class="tile"
        }
        """, css: ".lit { animation: spin 1s infinite; } .lit:hover { opacity: 0.5; } .other { filter: blur(1px); }")
        let styles = session.context.styles
        let elements = try #require(session.surfaces.first).root.map(StyleResolver.staticSubject(for:))
        #expect(elements[0].classes == ["tile", "lit"] && !elements[0].anyClass)
        #expect(styles.declares("animation", elements[0]))
        #expect(styles.stateStyled(.hover, elements[0]))
        #expect(!styles.declares("filter", elements[0]))
        #expect(elements[1].anyClass && elements[2].anyClass)
        #expect(styles.declares("filter", elements[1]))
        #expect(!styles.declares("animation", elements[3]))
        #expect(!styles.stateStyled(.hover, elements[3]))
    }

    @Test("animation nur unter :hover zählt schon im Ruhezustand, damit Hover den Zweig nicht wechselt")
    func hoverOnlyAnimation() throws {
        let (session, _) = try RenderProbe.session("panel \"t\" anchor=\"left\" { stack class=\"h\" }", css: ".h:hover { animation: pulse 1s infinite; }")
        let element = try #require(session.surfaces.first?.root.first)
        #expect(session.context.styles.declares("animation", StyleResolver.staticSubject(for: element)))
    }
}
