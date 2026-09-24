import Testing
import Foundation
import ApolloBase
@testable import ApolloConfig

@Suite("Auswertung von Ausdrücken")
struct EvaluatorTests {
    static let scope = TestScope(
        locals: [
            "a": .number(10),
            "b": .number(3),
            "a-b": .number(5),
            "list": .list([.number(1), .number(2), .number(3)]),
            "rec": .record(Record([("key", .string("v")), ("name", .string("R"))])),
            "left": .record(Record([("x", .number(1)), ("y", .list([.number(2)]))])),
            "right": .record(Record([("y", .list([.number(2)])), ("x", .number(1))])),
            "early": .date(Date(timeIntervalSince1970: 100)),
            "late": .date(Date(timeIntervalSince1970: 200)),
            "empty": .string(""),
        ],
        globals: [
            "perf": .record(Record([
                ("cpu", .number(0.42)),
                ("live", .record(Record([("memory-used", .number(2_147_483_648))]))),
            ])),
            "media": .record(Record([("artist", .string("Band"))])),
            "var": .record(Record([("index", .number(1)), ("items", .list([.string("x"), .string("y")]))])),
        ]
    )

    struct Case: Sendable, CustomTestStringConvertible {
        let source: String
        let expected: Value
        let warnings: Int

        init(_ source: String, _ expected: Value, warnings: Int = 0) {
            self.source = source
            self.expected = expected
            self.warnings = warnings
        }

        var testDescription: String { source }
    }

    static let cases: [Case] = [
        Case("1 + 2 * 3", .number(7)),
        Case("(1 + 2) * 3", .number(9)),
        Case("10 - 4 - 3", .number(3)),
        Case("2 * 3 % 4", .number(2)),
        Case("-2 * 3", .number(-6)),
        Case("a-b", .number(5)),
        Case("a - b", .number(7)),
        Case("a -b", .number(7)),
        Case("1 < 2 == true", .bool(true)),
        Case("1 + 1 == 2 && 3 > 2", .bool(true)),
        Case("false || null ?? true", .bool(false)),
        Case("null ?? 1 + 1", .number(2)),
        Case("false ? 1 : true ? 2 : 3", .number(2)),
        Case("empty ? 1 : 2", .number(2)),
        Case("[] ? 1 : 2", .number(2)),
        Case("0 ? 1 : 2", .number(2)),
        Case("rec ? 1 : 2", .number(1)),
        Case("!0", .bool(true)),
        Case("!'x'", .bool(false)),
        Case("'it\\'s'", .string("it's")),
        Case("'a' + 1", .string("a1")),
        Case("1 + 'a'", .string("1a")),
        Case("'n: ' + null", .string("n: ")),
        Case("null + 1", .null),
        Case("null * 2", .null),
        Case("1 + true", .null, warnings: 1),
        Case("'a' * 2", .null, warnings: 1),
        Case("1 / 0", .null),
        Case("5 % 0", .null),
        Case("7 % 3", .number(1)),
        Case("1 / 4", .number(0.25)),
        Case("-'a'", .null, warnings: 1),
        Case("-null", .null),
        Case("list[0]", .number(1)),
        Case("list[-1]", .number(3)),
        Case("list[3]", .null),
        Case("list[-4]", .null),
        Case("list[0.5]", .null, warnings: 1),
        Case("list[null]", .null),
        Case("[1, 2, 3][1]", .number(2)),
        Case("'abc'[1]", .string("b")),
        Case("'abc'[5]", .null),
        Case("rec['key']", .string("v")),
        Case("rec['missing']", .null),
        Case("rec.name", .string("R")),
        Case("rec[0]", .null, warnings: 1),
        Case("rec.name.first", .null, warnings: 1),
        Case("perf.cpu", .number(0.42)),
        Case("perf.live.memory-used", .number(2_147_483_648)),
        Case("media.title", .null),
        Case("media.title.length", .null),
        Case("media.title ?? 'none'", .string("none")),
        Case("media.artist ?? 'none'", .string("Band")),
        Case("missing.field.deeper", .null),
        Case("var.items[var.index]", .string("y")),
        Case("[1, [2, 3]] == [1, [2, 3]]", .bool(true)),
        Case("[1, 2] == [2, 1]", .bool(false)),
        Case("left == right", .bool(true)),
        Case("1 == '1'", .bool(false)),
        Case("null == null", .bool(true)),
        Case("null != 0", .bool(true)),
        Case("'b' > 'a'", .bool(true)),
        Case("'a' >= 'a'", .bool(true)),
        Case("early < late", .bool(true)),
        Case("late <= early", .bool(false)),
        Case("1 < 'a'", .null, warnings: 1),
        Case("[1] < [2]", .null, warnings: 1),
        Case("null < 1", .null),
        Case("[a, b + 1]", .list([.number(10), .number(4)])),
    ]

    @Test("Operatoren, Vorrang, Null-Fortpflanzung, Vergleich und Indizes", arguments: EvaluatorTests.cases)
    func evaluates(testCase: Case) throws {
        let sink = WarningSink()
        let evaluator = EvaluationHarness.evaluator(sink: sink)
        let value = evaluator.evaluate(try EvaluationHarness.expression(testCase.source), in: Self.scope)
        #expect(value == testCase.expected)
        #expect(sink.diagnostics.count == testCase.warnings)
        #expect(sink.diagnostics.allSatisfy { $0.severity == .warning })
    }

    static let messages: [(String, String)] = [
        ("1 + true", "cannot add a number and a bool"),
        ("'a' * 2", "cannot apply '*' to a string and a number"),
        ("-'a'", "cannot negate a string"),
        ("list[0.5]", "a list index must be a whole number"),
        ("rec[0]", "cannot index a record with a number"),
        ("rec.name.first", "a string has no field 'first'"),
        ("1 < 'a'", "cannot compare a number with a string"),
        ("list[1000000001]", "a list index is out of range"),
    ]

    @Test("Warntexte", arguments: EvaluatorTests.messages)
    func warningTexts(source: String, message: String) throws {
        let sink = WarningSink()
        _ = EvaluationHarness.evaluator(sink: sink).evaluate(try EvaluationHarness.expression(source), in: Self.scope)
        #expect(sink.diagnostics.map(\.message) == [message])
    }

    static let doubling = FilterTable(entries: [:]).adding("twice") { input, _, _ in
        guard case .number(let number) = input else { return .failure("'twice' expects a number") }
        return .value(.number(number * 2))
    }

    @Test("Pipe bindet am schwächsten, Filterfehler und unbekannte Filter ergeben null mit Warnung")
    func pipes() throws {
        let sink = WarningSink()
        let evaluator = EvaluationHarness.evaluator(filters: Self.doubling, sink: sink)
        #expect(evaluator.evaluate(try EvaluationHarness.expression("1 + 2 | twice"), in: Self.scope) == .number(6))
        #expect(evaluator.evaluate(try EvaluationHarness.expression("(a | twice) + 1"), in: Self.scope) == .number(21))
        #expect(evaluator.evaluate(try EvaluationHarness.expression("'x' | twice"), in: Self.scope) == .null)
        #expect(evaluator.evaluate(try EvaluationHarness.expression("a | nope"), in: Self.scope) == .null)
        #expect(sink.diagnostics.map(\.message) == ["'twice' expects a number", "unknown filter 'nope'"])
    }

    @Test("Filterwarnungen tragen die Spanne des Filternamens")
    func filterWarningSpan() throws {
        let sink = WarningSink()
        let evaluator = EvaluationHarness.evaluator(filters: Self.doubling, sink: sink)
        let base = SourceSpan(
            file: "shell.kdl",
            start: SourcePosition(offset: 100, line: 3, column: 10),
            end: SourcePosition(offset: 113, line: 3, column: 23)
        )
        let expr = try ExpressionParser.parseExpression("'x' | twice", span: base).get()
        _ = evaluator.evaluate(expr, in: Self.scope)
        #expect(sink.diagnostics.first?.span?.start.column == 17)
        #expect(sink.diagnostics.first?.span?.end.column == 22)
    }

    @Test("Fehlendes Feld durch einen Filter: null bzw. leerer Text, keine Warnung")
    func missingFieldThroughFilter() throws {
        let shout = BuiltinFilter("shout", arity: FilterArity(0, 0)) { input, _, _ in
            .string(try input.textInput("shout").uppercased())
        }
        let table = FilterTable(entries: ["shout": FilterTable.Entry(function: { shout.run($0, $1, $2) }, arity: shout.arity)])
        let sink = WarningSink()
        let evaluator = EvaluationHarness.evaluator(filters: table, sink: sink)
        #expect(evaluator.evaluate(try EvaluationHarness.expression("media.title | shout"), in: Self.scope) == .null)
        let template = try ExpressionParser.parseTemplate("{media.title | shout}!", span: .synthetic("test")).get()
        #expect(evaluator.render(template, in: Self.scope) == .string("!"))
        #expect(evaluator.evaluate(try EvaluationHarness.expression("media.artist | shout"), in: Self.scope) == .string("BAND"))
        #expect(sink.diagnostics.isEmpty)
    }

    @Test("Eine Warnung erscheint einmal je Stelle, auch bei 60 Auswertungen")
    func warnsOncePerSite() throws {
        let sink = WarningSink()
        let evaluator = EvaluationHarness.evaluator(sink: sink)
        let expr = try EvaluationHarness.expression("1 + true")
        let first = SourceSpan(
            file: "a.kdl",
            start: SourcePosition(offset: 0, line: 1, column: 1),
            end: SourcePosition(offset: 10, line: 1, column: 11)
        )
        let second = SourceSpan(
            file: "a.kdl",
            start: SourcePosition(offset: 20, line: 2, column: 1),
            end: SourcePosition(offset: 30, line: 2, column: 11)
        )
        for _ in 0..<60 {
            _ = evaluator.evaluate(expr, in: Self.scope, at: first)
        }
        _ = evaluator.evaluate(expr, in: Self.scope, at: second)
        #expect(sink.diagnostics.count == 2)
        #expect(sink.diagnostics.map(\.span) == [first, second])
    }

    @Test("Globale Wurzeln bekommen die Felder bis zum ersten Index")
    func globalLookup() throws {
        let scope = RecordingScope()
        let evaluator = EvaluationHarness.evaluator(sink: WarningSink())
        let value = evaluator.evaluate(try EvaluationHarness.expression("perf.live.memory-used[0]"), in: scope)
        #expect(value == .number(7))
        #expect(scope.calls == [DependencyPath("perf", ["live", "memory-used"])])
    }

    @Test("Ein lokaler Name verdeckt die globale Wurzel")
    func localShadowsGlobal() throws {
        var scope = Self.scope
        scope.locals["perf"] = .record(Record([("cpu", .number(1))]))
        let evaluator = EvaluationHarness.evaluator(sink: WarningSink())
        #expect(evaluator.evaluate(try EvaluationHarness.expression("perf.cpu"), in: scope) == .number(1))
    }

    @Test("Vorlagen: ganzer Wert behält den Typ, gemischte Vorlagen ergeben Strings")
    func renders() throws {
        let evaluator = EvaluationHarness.evaluator(sink: WarningSink())
        func render(_ text: String) throws -> Value {
            evaluator.render(try ExpressionParser.parseTemplate(text, span: .synthetic("test")).get(), in: Self.scope)
        }
        #expect(try render("plain") == .string("plain"))
        #expect(try render("{perf.cpu}") == .number(0.42))
        #expect(try render("{list}") == .list([.number(1), .number(2), .number(3)]))
        #expect(try render("{a} and {media.title}") == .string("10 and "))
        #expect(try render("{{literal}}") == .string("{literal}"))
        #expect(try render("{list} items") == .string("[1,2,3] items"))
        #expect(try render("{early < late}!") == .string("true!"))
    }

    @Test("Nicht endliche Ergebnisse werden null")
    func nonFinite() throws {
        let huge = "1" + String(repeating: "0", count: 300)
        let evaluator = EvaluationHarness.evaluator(sink: WarningSink())
        #expect(evaluator.evaluate(try EvaluationHarness.expression("\(huge) * \(huge)"), in: Self.scope) == .null)
        #expect(evaluator.evaluate(try EvaluationHarness.expression("-\(huge) - \(huge) * \(huge)"), in: Self.scope) == .null)
    }

    @Test("256 verkettete Operatoren stürzen bei der Auswertung nicht ab")
    func deepChainEvaluates() throws {
        let source = Array(repeating: "1", count: 256).joined(separator: " + ")
        let expr = try EvaluationHarness.expression(source)
        let evaluator = EvaluationHarness.evaluator(sink: WarningSink())
        #expect(evaluator.evaluate(expr, in: Self.scope) == .number(256))
    }

    @MainActor
    @Test("Auf dem Main Thread bei genug Stapel kein Thread-Wechsel")
    func inlineOnMainThread() throws {
        let scope = MainThreadCheckingScope()
        let evaluator = EvaluationHarness.evaluator(sink: WarningSink())
        #expect(evaluator.evaluate(try EvaluationHarness.expression("a"), in: scope) == .bool(true))
    }
}
