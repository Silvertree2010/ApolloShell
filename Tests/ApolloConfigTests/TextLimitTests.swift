import Testing
import Foundation
import ApolloBase
@testable import ApolloConfig

@Suite("Obergrenze für erzeugte Texte")
struct TextLimitTests {
    static let big = Value.string(String(repeating: "x", count: 600_000))

    static func evaluate(_ source: String, _ locals: [String: Value]) throws -> (Value, [Diagnostic]) {
        let sink = WarningSink()
        let evaluator = EvaluationHarness.evaluator(sink: sink)
        let value = evaluator.evaluate(try EvaluationHarness.expression(source), in: TestScope(locals: locals))
        return (value, sink.diagnostics)
    }

    @Test("+ über der Grenze liefert null mit Warnung, darunter den Text")
    func plus() throws {
        let (over, warnings) = try Self.evaluate("a + a", ["a": Self.big])
        #expect(over == .null)
        #expect(warnings.map(\.message) == ["text would be longer than 1000000 bytes"])
        let (under, none) = try Self.evaluate("a + 'y'", ["a": Self.big])
        #expect(under == .string(String(repeating: "x", count: 600_000) + "y"))
        #expect(none.isEmpty)
    }

    @Test("Verkettung im Template über der Grenze liefert null mit Warnung")
    func template() throws {
        let sink = WarningSink()
        let evaluator = EvaluationHarness.evaluator(sink: sink)
        let template = try ExpressionParser.parseTemplate("{a}{a}", span: .synthetic("test")).get()
        let value = evaluator.render(template, in: TestScope(locals: ["a": Self.big]))
        #expect(value == .null)
        #expect(sink.diagnostics.map(\.message) == ["text would be longer than 1000000 bytes"])
    }

    @Test("replace und join brechen vor dem Erzeugen zu langer Texte ab")
    func filters() {
        let cases = [
            FilterCase.fails("replace", .string(String(repeating: "x", count: 1_000)), [.string("x"), .string(String(repeating: "y", count: 1_001))]),
            FilterCase.ok("replace", .string(String(repeating: "x", count: 1_000)), [.string("x"), .string(String(repeating: "y", count: 1_000))], .string(String(repeating: "y", count: 1_000_000))),
            FilterCase.ok("replace", .string("a" + String(repeating: "x", count: 999_998)), [.string("a"), .string("bb")], .string("bb" + String(repeating: "x", count: 999_998))),
            FilterCase.fails("join", .list(Array(repeating: .string("x"), count: 1_000)), [.string(String(repeating: "-", count: 1_001))]),
            FilterCase.ok("join", .list([.string("a"), .string("b")]), [.string("-")], .string("a-b")),
        ]
        for testCase in cases {
            FilterHarness.check(testCase)
        }
    }

    @Test("Verdoppeln per let endet an der Grenze statt den Speicher zu füllen")
    func doublingLets() {
        var lines = ["let v0=\"x\""]
        for index in 1...64 {
            lines.append("let v\(index)=\"{v\(index - 1) + v\(index - 1)}\"")
        }
        let result = LetStageTests.run(lines.joined(separator: "\n"))
        #expect(result.values["v19"] == .string(String(repeating: "x", count: 1 << 19)))
        #expect(result.values["v20"] == .null)
    }
}
