import Testing
import Foundation
import AppKit
import ApolloBase
import ApolloStyle
@testable import ApolloShell

@MainActor
@Suite("Render: Listen und Caches bleiben begrenzt", .serialized)
struct LifetimeTests {
    static let config = """
    var hit #false
    var show #true
    panel "t" anchor="left" {
        when "{var.show}" {
            button id="plain" class="b" { on-click { set "hit" #true } }
            button id="slow" class="b" { on-click throttle="1s" { set "hit" #true } }
        }
    }
    """
    static let css = "#t { width: 40px; height: 40px; } .b { width: 20px; height: 20px; }"

    @Test("erledigte Aktionen verlassen pending ohne settle, Gates nur mit Regeln und nur solange das Element lebt")
    func pendingAndGates() async throws {
        let mounted = try Mounted.mount(Self.config, css: Self.css)
        let context = mounted.session.context
        let plain = try #require(mounted.catcher("plain").element)
        for _ in 0..<50 { context.fire("on-click", plain) }
        for _ in 0..<40 where !context.pending.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(context.pending.isEmpty)
        #expect(context.gates.isEmpty)
        let slow = try #require(mounted.catcher("slow").element)
        context.fire("on-click", slow)
        #expect(context.gates.count == 1)
        context.runtime?.setVariable("show", .bool(false))
        mounted.session.flush()
        mounted.pump()
        #expect(context.gates.isEmpty)
    }

    @Test("Stil-Cache hat eine Obergrenze")
    func styleCacheBounded() {
        let resolver = StyleResolver(sheets: [], environment: StyleSheets.environment(dark: false, tokens: .empty))
        for index in 0..<(StyleResolver.cacheLimit + 500) {
            _ = resolver.resolve(StyleSubject(kind: "stack"), ancestors: [], parent: nil, inline: "width: \(index)px")
        }
        #expect(resolver.cachedCount <= StyleResolver.cacheLimit)
        let again = resolver.resolve(StyleSubject(kind: "stack"), ancestors: [], parent: nil, inline: "width: 3px")
        #expect(again["width"] != nil)
    }

    @Test("BoundedCache verdrängt die am längsten unbenutzten Einträge")
    func boundedCache() {
        var cache = BoundedCache<Int, Int>(limit: 4)
        for key in 0..<4 { cache[key] = key }
        _ = cache[0]
        cache[4] = 4
        cache[5] = 5
        #expect(cache.count <= 4)
        #expect(cache[0] == 0)
        #expect(cache[5] == 5)
    }

    static let reorderConfig = MenuReorderTests.reorderConfig.replacingOccurrences(of: "on-reorder {", with: "on-reorder debounce=\"500ms\" {")

    @Test("reorderable mit debounce: Vorschau bleibt, bis die eigene Aktion gelaufen ist")
    func reorderDebounced() async throws {
        let mounted = try Mounted.mount(Self.reorderConfig, css: MenuReorderTests.reorderCSS)
        let context = mounted.session.context
        let list = try #require(context.reorders.values.first)
        let a = list.entry(for: list.container.children[0], index: 0)
        let c = list.entry(for: list.container.children[2], index: 2)
        #expect(list.drop(token: a.token, on: c))
        try await Task.sleep(for: .milliseconds(420))
        #expect(list.preview != nil)
        for _ in 0..<60 where mounted.variable("log") == .string("") { try await Task.sleep(for: .milliseconds(25)) }
        #expect(mounted.variable("log") == .string("0>3 a a>c"))
    }
}
