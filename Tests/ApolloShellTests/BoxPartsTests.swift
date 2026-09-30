import Testing
import ApolloStyle
@testable import ApolloShell

@MainActor
@Suite("Elemente bekommen nur die Modifier, deren Eigenschaft deklariert sein kann")
struct BoxPartsTests {
    @Test("Ein Element ohne die Eigenschaften bekommt keinen der Modifier")
    func bare() throws {
        let (session, _) = try RenderProbe.session("""
        panel "t" anchor="left" {
            stack class="bare"
            stack class="full"
        }
        """, css: ".full { padding-left: 4px; margin: 2px; width: 10px; aspect-ratio: 1; background-color: red; border: 1px solid red; overflow: hidden; opacity: 0.5; transform: scale(2); z-index: 2; cursor: pointer; pointer-events: none; transition: opacity 1s; }")
        let styles = session.context.styles
        let elements = try #require(session.surfaces.first).root
        let bare = styles.parts(StyleResolver.staticSubject(for: elements[0]))
        let none = BoxParts(styles: styles, subject: StaticSubject(kind: "-none"))
        #expect(bare == none)
        #expect(!bare.padding && !bare.margin && !bare.size && !bare.aspect && !bare.paint && !bare.border && !bare.clip)
        #expect(!bare.opacity && !bare.transform && !bare.depth && !bare.pointer && !bare.cursor && !bare.motion)
        let plan = ElementView.plan(elements[0], styles: styles, inherited: InheritedParts(pointer: false, cursor: false))
        #expect(!plan.motion && !plan.parts.pointer && !plan.parts.cursor)
        let full = styles.parts(StyleResolver.staticSubject(for: elements[1]))
        #expect(full.padding && full.margin && full.size && full.aspect && full.paint && full.border && full.clip)
        #expect(full.opacity && full.transform && full.depth && full.pointer && full.cursor && full.motion)
    }

    @Test("vererbte Eigenschaften zählen über die Vorfahren, none gehört dazu")
    func inherited() throws {
        let (session, _) = try RenderProbe.session("""
        panel "t" anchor="left" {
            stack class="a"
            stack class="b"
        }
        """, css: ".a { pointer-events: none; }")
        let styles = session.context.styles
        let elements = try #require(session.surfaces.first).root
        #expect(ElementView.plan(elements[0], styles: styles, inherited: InheritedParts(pointer: false, cursor: false)).parts.pointer)
        #expect(!ElementView.plan(elements[1], styles: styles, inherited: InheritedParts(pointer: false, cursor: false)).parts.pointer)
        #expect(ElementView.plan(elements[1], styles: styles, inherited: InheritedParts(pointer: true, cursor: false)).parts.pointer)
    }

    @Test("Inline-Stil schaltet alles ein")
    func inline() throws {
        let (session, _) = try RenderProbe.session("panel \"t\" anchor=\"left\" { stack style=\"opacity: 0.5\" }", css: "")
        let element = try #require(session.surfaces.first?.root.first)
        let plan = ElementView.plan(element, styles: session.context.styles, inherited: InheritedParts(pointer: false, cursor: false))
        #expect(plan.parts == BoxParts.all && plan.motion)
    }
}
