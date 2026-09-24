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
        func subject(_ index: Int) -> StyleSubject { StyleResolver.subject(for: elements[index]) }
        #expect(styles.declares("animation", subject(0), ancestors: [], parent: nil, inline: nil))
        #expect(styles.declares("filter", subject(0), ancestors: [], parent: nil, inline: nil))
        #expect(!styles.declares("animation", subject(2), ancestors: [], parent: nil, inline: nil))
        #expect(!styles.declares("filter", subject(2), ancestors: [], parent: nil, inline: nil))
        #expect(styles.sensitive(to: .hover, subject(1), ancestors: [], parent: nil, inline: nil))
        #expect(!ElementView.needsInteraction(elements[2], styles: styles, reorder: false))
        #expect(ElementView.needsInteraction(elements[1], styles: styles, reorder: false, stateStyled: true))
    }

    @Test("animation nur unter :hover zählt schon im Ruhezustand, damit Hover den Zweig nicht wechselt")
    func hoverOnlyAnimation() throws {
        let (session, _) = try RenderProbe.session("panel \"t\" anchor=\"left\" { stack class=\"h\" }", css: ".h:hover { animation: pulse 1s infinite; }")
        let element = try #require(session.surfaces.first?.root.first)
        #expect(session.context.styles.declares("animation", StyleResolver.subject(for: element), ancestors: [], parent: nil, inline: nil))
    }
}
