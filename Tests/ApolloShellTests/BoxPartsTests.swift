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

    @Test("Inline-Stil schaltet nur die Teile ein, die er deklariert")
    func inline() throws {
        let (session, _) = try RenderProbe.session("panel \"t\" anchor=\"left\" { stack style=\"opacity: 0.5; padding-left: 2px; filter: blur(2px)\" }", css: "")
        let element = try #require(session.surfaces.first?.root.first)
        let styles = session.context.styles
        let plan = ElementView.plan(element, styles: styles, inherited: InheritedParts(pointer: false, cursor: false), inline: "opacity: 0.5; padding-left: 2px; filter: blur(2px)")
        #expect(plan.parts.opacity && plan.parts.padding && plan.inline.filter)
        #expect(!plan.parts.margin && !plan.parts.transform && !plan.parts.paint && !plan.parts.pointer && !plan.motion && !plan.inline.animation)
        let moving = ElementView.plan(element, styles: styles, inherited: InheritedParts(pointer: false, cursor: false), inline: "transition: opacity 1s")
        #expect(moving.motion && !moving.parts.opacity)
        let empty = ElementView.plan(element, styles: styles, inherited: InheritedParts(pointer: false, cursor: false), inline: "")
        #expect(empty.parts == styles.parts(StyleResolver.staticSubject(for: element)).merged(BoxParts(names: [])) && !empty.motion)
    }
}
