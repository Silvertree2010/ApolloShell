import Testing
import Foundation
import AppKit
import ApolloBase
import ApolloRuntime
@testable import ApolloShell

@MainActor
@Suite("Render: Stilwechsel baut keinen Unterbaum neu", .serialized)
struct IdentityTests {
    static let config = """
    var appeared 0
    var gone 0
    panel "t" anchor="left" {
        stack id="box" class="box" tooltip="{var.gone > 5 ? 'tip' : ''}" {
            on-appear { set "appeared" "{var.appeared + 1}" }
            on-disappear { set "gone" "{var.gone + 1}" }
            stack class="inner"
        }
    }
    """
    static let css = """
    #t { width: 60px; height: 60px; align-items: start; }
    .box { width: 40px; height: 40px; }
    .box:hover { background: #ff0000; overflow: hidden; aspect-ratio: 1; filter: blur(1px); cursor: pointer; animation: spin 1s infinite; transition: background 100ms; }
    .inner { width: 10px; height: 10px; }
    """

    @Test("Hover-Stil mit Hintergrund, Clip, Seitenverhältnis, Filter, Cursor und Animation: on-appear/on-disappear feuern nicht erneut")
    func hoverKeepsIdentity() async throws {
        let mounted = try Mounted.mount(Self.config, css: Self.css)
        await mounted.settle()
        #expect(mounted.variable("appeared") == .number(1))
        let box = try #require(Self.find("box", in: mounted))
        for _ in 0..<3 {
            box.pseudo.insert(.hover)
            mounted.pump(5)
            await mounted.settle()
            box.pseudo.remove(.hover)
            mounted.pump(5)
            await mounted.settle()
        }
        #expect(mounted.variable("appeared") == .number(1))
        #expect(mounted.variable("gone") == .number(0))
    }

    static let scrollConfig = """
    var items "{['a', 'b']}"
    var appeared 0
    panel "t" anchor="left" {
        scroll class="s" {
            each item in="{var.items}" key="{item}" {
                stack class="item" { on-appear { set "appeared" "{var.appeared + 1}" } }
            }
        }
    }
    """
    static let scrollCSS = """
    #t { width: 40px; height: 50px; align-items: start; }
    .s { width: 40px; height: 50px; }
    .item { width: 40px; height: 20px; }
    """

    @Test("scroll beim Übergang ins Scrollen: nur das neue Kind feuert on-appear, :overflowing wird gesetzt")
    func scrollKeepsIdentity() async throws {
        let mounted = try Mounted.mount(Self.scrollConfig, css: Self.scrollCSS)
        await mounted.settle()
        #expect(mounted.variable("appeared") == .number(2))
        let scroll = try #require(Self.all(in: mounted).first { $0.kind == "scroll" })
        #expect(!scroll.pseudo.contains(.overflowing))
        mounted.session.context.runtime?.setVariable("items", .list([.string("a"), .string("b"), .string("c")]))
        mounted.session.flush()
        mounted.pump(10)
        await mounted.settle()
        #expect(mounted.variable("appeared") == .number(3))
        #expect(scroll.pseudo.contains(.overflowing))
    }

    @Test("self.hover und self.pressed in Ausdrücken schalten die Verfolgung ein, auch ohne Handler")
    func selfStateTracking() throws {
        let (session, _) = try RenderProbe.session("""
        panel "t" anchor="left" {
            stack id="hot" class="{self.hover ? 'hot' : ''}"
            stack id="press" class="{self.pressed ? 'down' : ''}"
            stack id="plain"
        }
        """)
        let elements = try #require(session.surfaces.first).root
        let hot = try #require(elements.first { $0.property("id").plainText == "hot" })
        let press = try #require(elements.first { $0.property("id").plainText == "press" })
        let plain = try #require(elements.first { $0.property("id").plainText == "plain" })
        #expect(SelfState.uses(hot, "hover"))
        #expect(!SelfState.uses(hot, "pressed"))
        #expect(SelfState.uses(press, "pressed"))
        #expect(!SelfState.uses(plain, "hover"))
        #expect(ElementView.needsInteraction(hot, styles: session.context.styles, reorder: false))
        #expect(ElementView.needsInteraction(press, styles: session.context.styles, reorder: false))
        #expect(!ElementView.needsInteraction(plain, styles: session.context.styles, reorder: false))
    }

    static func all(in mounted: Mounted) -> [ElementInstance] {
        func walk(_ list: [ElementInstance]) -> [ElementInstance] { list.flatMap { [$0] + walk($0.children) } }
        return walk(mounted.session.surfaces.first?.root ?? [])
    }

    static func find(_ id: String, in mounted: Mounted) -> ElementInstance? {
        all(in: mounted).first { $0.property("id").plainText == id }
    }
}
