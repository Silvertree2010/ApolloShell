import Testing
import ApolloBase
@testable import ApolloConfig

@Suite("Abhängigkeiten von Ausdrücken")
struct DependencyTests {
    static func dependencies(_ source: String, locals: Set<String>) throws -> Set<DependencyPath> {
        try ExpressionParser.parseExpression(source, span: .synthetic("test")).get().dependencies(locals: locals)
    }

    static func template(_ text: String) throws -> StringTemplate {
        try ExpressionParser.parseTemplate(text, span: .synthetic("test")).get()
    }

    static let cases: [(String, Set<String>, Set<DependencyPath>)] = [
        ("perf.cpu", [], [DependencyPath("perf", ["cpu"])]),
        ("perf.live.memory-used / 1073741824", [], [DependencyPath("perf", ["live", "memory-used"])]),
        ("list[i]", [], [DependencyPath("list"), DependencyPath("i")]),
        ("var.items[var.index].name", [], [DependencyPath("var", ["items"]), DependencyPath("var", ["index"])]),
        ("app.name", ["app"], []),
        ("app.icons[var.size]", ["app"], [DependencyPath("var", ["size"])]),
        ("clock.now | relative", [], [DependencyPath("clock", ["now"])]),
        ("x | relative", ["x"], [DependencyPath("clock", ["now"])]),
        ("(a ?? b).c", [], [DependencyPath("a"), DependencyPath("b")]),
        ("a ? b.c : !d", [], [DependencyPath("a"), DependencyPath("b", ["c"]), DependencyPath("d")]),
        ("[x, y.z]", [], [DependencyPath("x"), DependencyPath("y", ["z"])]),
        ("1 + 2 * 3", [], []),
        ("list | where 'kind' var.kind", [], [DependencyPath("list"), DependencyPath("var", ["kind"])]),
        ("-self.hover", [], [DependencyPath("self", ["hover"])]),
        ("'abc'[var.i]", [], [DependencyPath("var", ["i"])]),
        ("module.kind == 'clock' && var.editing", ["module"], [DependencyPath("var", ["editing"])]),
    ]

    @Test("Pfade bis zum ersten Index, lokale Namen ausgenommen, relative hängt an clock.now", arguments: DependencyTests.cases)
    func collects(source: String, locals: Set<String>, expected: Set<DependencyPath>) throws {
        #expect(try Self.dependencies(source, locals: locals) == expected)
    }

    @Test("Vorlagen: Abhängigkeiten aller Teile, konstant nur ohne jeden Pfad")
    func templates() throws {
        #expect(try Self.template("plain").dependencies(locals: []).isEmpty)
        #expect(try Self.template("plain").isConstant)
        #expect(try Self.template("{1 + 2} items").isConstant)
        #expect(try Self.template("{'a' | upper}").isConstant)
        #expect(try Self.template("{i + 1}").isConstant == false)
        #expect(try Self.template("{i + 1}").dependencies(locals: ["i"]).isEmpty)
        #expect(try Self.template("{'2026' | relative}").isConstant == false)
        #expect(try Self.template("{a.b} of {c}").dependencies(locals: []) == [DependencyPath("a", ["b"]), DependencyPath("c")])
    }

    @Test("256 verkettete Operatoren stürzen nicht ab")
    func deepChain() throws {
        let source = Array(repeating: "a", count: 256).joined(separator: " + ")
        let expr = try ExpressionParser.parseExpression(source, span: .synthetic("test")).get()
        #expect(expr.dependencies(locals: []) == [DependencyPath("a")])
    }
}
