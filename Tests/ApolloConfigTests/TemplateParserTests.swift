import Testing
import ApolloBase
@testable import ApolloConfig

@Suite("Vorlagen in Strings")
struct TemplateParserTests {
    static let span = SourceSpan.synthetic("test")

    static func parse(_ text: String) -> Result<StringTemplate, Diagnostic> {
        ExpressionParser.parseTemplate(text, span: span)
    }

    static func path(_ root: String, _ fields: String...) -> Expr {
        .path(root: root, members: fields.map { .field($0) })
    }

    static let valid: [(String, StringTemplate)] = [
        ("plain", .literal("plain")),
        ("", .literal("")),
        ("a}}b", .literal("a}}b")),
        ("{x}", .whole(path("x"))),
        (" {x}", .parts([.text(" "), .expression(path("x"))])),
        ("{battery.percent | percent} left", .parts([
            .expression(.pipe(path("battery", "percent"), FilterCall(name: "percent", span: span))),
            .text(" left"),
        ])),
        ("{{x}}", .literal("{x}")),
        ("{{{x}}}", .parts([.text("{"), .expression(path("x")), .text("}")])),
        ("{a}{b}", .parts([.expression(path("a")), .expression(path("b"))])),
        ("{'}'}", .whole(.literal(.string("}")))),
        ("{'{{'}", .whole(.literal(.string("{{")))),
        ("{media.artist ?? 'Unknown'}", .whole(.coalesce(path("media", "artist"), .literal(.string("Unknown"))))),
        ("{i + 1}. {app.name}", .parts([
            .expression(.binary(.add, path("i"), .literal(.number(1)))),
            .text(". "),
            .expression(path("app", "name")),
        ])),
    ]

    @Test("gültige Vorlagen", arguments: TemplateParserTests.valid)
    func parsesValid(text: String, expected: StringTemplate) throws {
        #expect(try Self.parse(text).get() == expected)
    }

    static let invalid: [(String, String, String?)] = [
        ("{x", "unclosed '{'", "close the expression with '}' or write '{{' for a literal brace"),
        ("{'abc}", "unclosed '{'", "close the expression with '}' or write '{{' for a literal brace"),
        ("{x}}", "unmatched '}'", "write '}}' for a literal brace"),
        ("{}", "empty expression", "write '{{}}' for literal braces"),
        ("{ }", "empty expression", "write '{{}}' for literal braces"),
        ("{a {b}}", "'{' inside an expression", "expressions cannot be nested; close the first one with '}'"),
        ("{a +}", "expected an expression, found end of expression", nil),
        ("x {Foo}", "unexpected character 'F'", "names are lowercase kebab-case"),
    ]

    @Test("ungültige Vorlagen ergeben eine Diagnose", arguments: TemplateParserTests.invalid)
    func rejectsInvalid(text: String, message: String, help: String?) {
        guard case .failure(let diagnostic) = Self.parse(text) else {
            Issue.record("expected a diagnostic for \(text)")
            return
        }
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message == message)
        #expect(diagnostic.help == help)
    }

    static func base(endColumn: Int) -> SourceSpan {
        SourceSpan(
            file: "shell.kdl",
            start: SourcePosition(offset: 100, line: 3, column: 10),
            end: SourcePosition(offset: 100 + endColumn - 10, line: 3, column: endColumn)
        )
    }

    @Test("Spannen in Vorlagen: Filtername, Klammerfehler und Fehler im Ausdruck")
    func spans() throws {
        let template = try ExpressionParser.parseTemplate("{a | rond}", span: Self.base(endColumn: 22)).get()
        guard case .whole(.pipe(_, let call)) = template else {
            Issue.record("expected a whole pipe")
            return
        }
        #expect(call.span.start == SourcePosition(offset: 106, line: 3, column: 16))
        #expect(call.span.end == SourcePosition(offset: 110, line: 3, column: 20))

        guard case .failure(let brace) = ExpressionParser.parseTemplate("{x}} y", span: Self.base(endColumn: 18)) else {
            Issue.record("expected a brace diagnostic")
            return
        }
        #expect(brace.span?.start.column == 14)
        #expect(brace.span?.end.column == 15)

        guard case .failure(let inner) = ExpressionParser.parseTemplate("{a = b}", span: Self.base(endColumn: 19)) else {
            Issue.record("expected an expression diagnostic")
            return
        }
        #expect(inner.span?.start.column == 14)
        #expect(inner.span?.end.column == 15)
    }
}
