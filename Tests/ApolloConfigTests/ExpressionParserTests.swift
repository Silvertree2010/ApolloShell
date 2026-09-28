import Testing
import ApolloBase
@testable import ApolloConfig

@Suite("Parser für Ausdrücke")
struct ExpressionParserTests {
    static let span = SourceSpan.synthetic("test")

    static func path(_ root: String, _ fields: String...) -> Expr {
        .path(root: root, members: fields.map { .field($0) })
    }

    static func number(_ value: Double) -> Expr { .literal(.number(value)) }

    static func text(_ value: String) -> Expr { .literal(.string(value)) }

    static func filter(_ name: String, _ arguments: [Expr] = []) -> FilterCall {
        FilterCall(name: name, arguments: arguments, span: span)
    }

    static func parse(_ source: String) -> Result<Expr, Diagnostic> {
        ExpressionParser.parseExpression(source, span: span)
    }

    static let valid: [(String, Expr)] = [
        ("1 + 2 * 3", .binary(.add, number(1), .binary(.multiply, number(2), number(3)))),
        ("a-b", path("a-b")),
        ("a - b", .binary(.subtract, path("a"), path("b"))),
        ("10 - 4 - 3", .binary(.subtract, .binary(.subtract, number(10), number(4)), number(3))),
        ("a || b && c == 1 + 2 * 3", .binary(.or, path("a"), .binary(.and, path("b"), .binary(.equal, path("c"), .binary(.add, number(1), .binary(.multiply, number(2), number(3))))))),
        ("1 * 2 + 3 < 4 == d && e || f", .binary(.or, .binary(.and, .binary(.equal, .binary(.less, .binary(.add, .binary(.multiply, number(1), number(2)), number(3)), number(4)), path("d")), path("e")), path("f"))),
        ("8 / 4 / 2 % 3", .binary(.remainder, .binary(.divide, .binary(.divide, number(8), number(4)), number(2)), number(3))),
        ("1 + 2 * 3 - 4", .binary(.subtract, .binary(.add, number(1), .binary(.multiply, number(2), number(3))), number(4))),
        ("a < b != c >= d", .binary(.notEqual, .binary(.less, path("a"), path("b")), .binary(.greaterOrEqual, path("c"), path("d")))),
        ("app.bundle-id", path("app", "bundle-id")),
        ("a || b && c", .binary(.or, path("a"), .binary(.and, path("b"), path("c")))),
        ("a == b != c", .binary(.notEqual, .binary(.equal, path("a"), path("b")), path("c"))),
        ("a < b == c >= d", .binary(.equal, .binary(.less, path("a"), path("b")), .binary(.greaterOrEqual, path("c"), path("d")))),
        ("a % b * c", .binary(.multiply, .binary(.remainder, path("a"), path("b")), path("c"))),
        ("a ?? b ?? c", .coalesce(.coalesce(path("a"), path("b")), path("c"))),
        ("a || b ?? c", .coalesce(.binary(.or, path("a"), path("b")), path("c"))),
        ("a ? b : c ? d : e", .conditional(path("a"), path("b"), .conditional(path("c"), path("d"), path("e")))),
        ("a ?? b ? c : d", .conditional(.coalesce(path("a"), path("b")), path("c"), path("d"))),
        ("!a && -b", .binary(.and, .unary(.not, path("a")), .unary(.negate, path("b")))),
        ("--a", .unary(.negate, .unary(.negate, path("a")))),
        ("a + b | round", .pipe(.binary(.add, path("a"), path("b")), filter("round"))),
        ("x | clamp 0 9 | fixed 1", .pipe(.pipe(path("x"), filter("clamp", [number(0), number(9)])), filter("fixed", [number(1)]))),
        ("list | where 'kind' var.k", .pipe(path("list"), filter("where", [text("kind"), path("var", "k")]))),
        ("a ? b : c | upper", .pipe(.conditional(path("a"), path("b"), path("c")), filter("upper"))),
        ("list[0].name", .path(root: "list", members: [.index(number(0)), .field("name")])),
        ("list[-1]", .path(root: "list", members: [.index(.unary(.negate, number(1)))])),
        ("rec['key']", .path(root: "rec", members: [.index(text("key"))])),
        ("var.items[var.index]", .path(root: "var", members: [.field("items"), .index(path("var", "index"))])),
        ("(a | first).name", .access(.pipe(path("a"), filter("first")), [.field("name")])),
        ("(a).b", path("a", "b")),
        ("'abc'[1]", .access(text("abc"), [.index(number(1))])),
        ("[1, 'two', true, null]", .list([number(1), text("two"), .literal(.bool(true)), .literal(.null)])),
        ("[]", .list([])),
        ("[a | upper, b]", .list([.pipe(path("a"), filter("upper")), path("b")])),
        ("'it\\'s \\\\ ok'", text("it's \\ ok")),
        ("media.artist ?? 'Unknown'", .coalesce(path("media", "artist"), text("Unknown"))),
        ("true-ish", path("true-ish")),
        ("x.null", path("x", "null")),
        ("3.25", number(3.25)),
        ("(1 + 2) * 3", .binary(.multiply, .binary(.add, number(1), number(2)), number(3))),
        ("x | contains [1, 2]", .pipe(path("x"), filter("contains", [.list([number(1), number(2)])]))),
        ("list[0][1]", .path(root: "list", members: [.index(number(0)), .index(number(1))])),
        (
            "apps.dock | index-where 'section' ['running']",
            .pipe(path("apps", "dock"), filter("index-where", [text("section"), .list([text("running")])]))
        ),
        (
            "x | zip [1, 2] [3, 4]",
            .pipe(path("x"), filter("zip", [.list([number(1), number(2)]), .list([number(3), number(4)])]))
        ),
    ]

    @Test("gültige Ausdrücke ergeben den erwarteten Baum", arguments: ExpressionParserTests.valid)
    func parsesValid(source: String, expected: Expr) throws {
        #expect(try Self.parse(source).get() == expected)
    }

    static let invalid: [(String, String, String?)] = [
        ("a = b", "unexpected '='", "use '==' to compare values"),
        ("'abc", "unterminated string", "close the string with a single quote"),
        ("a +", "expected an expression, found end of expression", nil),
        ("", "expected an expression, found end of expression", nil),
        ("(a", "expected ')', found end of expression", nil),
        ("[1, 2", "expected ',' or ']' in the list, found end of expression", nil),
        ("a ? b", "expected ':' after the '?' branch, found end of expression", nil),
        ("a | ", "expected a filter name after '|', found end of expression", nil),
        ("a | 5", "expected a filter name after '|', found '5'", nil),
        ("a | round 2 + 1", "unexpected '+'", "filter arguments are simple values; wrap a computed argument in parentheses"),
        ("a.0", "expected a field name after '.', found '0'", "use [0] to take an element of a list"),
        ("1.", "expected a field name after '.', found end of expression", nil),
        ("a b", "unexpected 'b'", nil),
        ("a)", "unexpected ')'", nil),
        ("list[0", "expected ']' after the index, found end of expression", nil),
        ("a [0]", "unexpected '['", nil),
    ]

    @Test("ungültige Ausdrücke ergeben eine Diagnose mit Text und Hilfe", arguments: ExpressionParserTests.invalid)
    func rejectsInvalid(source: String, message: String, help: String?) {
        guard case .failure(let diagnostic) = Self.parse(source) else {
            Issue.record("expected a diagnostic for \(source)")
            return
        }
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message == message)
        #expect(diagnostic.help == help)
    }

    @Test("32 Klammerebenen gehen, 40 sind ein Fehler statt eines Stack-Überlaufs")
    func nesting() throws {
        let allowed = String(repeating: "(", count: 32) + "a" + String(repeating: ")", count: 32)
        #expect(try Self.parse(allowed).get() == Self.path("a"))
        let deep = String(repeating: "(", count: 40) + "a" + String(repeating: ")", count: 40)
        guard case .failure(let diagnostic) = Self.parse(deep) else {
            Issue.record("expected a nesting diagnostic")
            return
        }
        #expect(diagnostic.message == "expression is nested too deeply")
        let negations = String(repeating: "!", count: 40) + "a"
        guard case .failure(let negationDiagnostic) = Self.parse(negations) else {
            Issue.record("expected a nesting diagnostic for prefix operators")
            return
        }
        #expect(negationDiagnostic.message == "expression is nested too deeply")
    }

    static let base = SourceSpan(
        file: "shell.kdl",
        start: SourcePosition(offset: 100, line: 3, column: 10),
        end: SourcePosition(offset: 112, line: 3, column: 20)
    )

    @Test("FilterCall trägt die Spanne seines Namens in der Datei")
    func filterSpan() throws {
        let expr = try ExpressionParser.parseExpression("a | rond", span: Self.base).get()
        guard case .pipe(_, let call) = expr else {
            Issue.record("expected a pipe")
            return
        }
        #expect(call.span == SourceSpan(
            file: "shell.kdl",
            start: SourcePosition(offset: 105, line: 3, column: 15),
            end: SourcePosition(offset: 109, line: 3, column: 19)
        ))
    }

    @Test("Spalten zählen Zeichen, Offsets UTF-8-Bytes, auch nach einem Umlaut")
    func unicodeSpan() throws {
        let base = SourceSpan(
            file: "shell.kdl",
            start: SourcePosition(offset: 100, line: 3, column: 10),
            end: SourcePosition(offset: 113, line: 3, column: 22)
        )
        let expr = try ExpressionParser.parseExpression("'ä' | rond", span: base).get()
        guard case .pipe(_, let call) = expr else {
            Issue.record("expected a pipe")
            return
        }
        #expect(call.span.start == SourcePosition(offset: 108, line: 3, column: 17))
        #expect(call.span.end == SourcePosition(offset: 112, line: 3, column: 21))
    }

    @Test("Diagnosen zeigen auf die Fehlerstelle, mehrzeilige Strings auf den ganzen String")
    func diagnosticSpan() {
        guard case .failure(let diagnostic) = ExpressionParser.parseExpression("a = b", span: Self.base) else {
            Issue.record("expected a diagnostic")
            return
        }
        #expect(diagnostic.span?.start.column == 13)
        #expect(diagnostic.span?.end.column == 14)
        let multiline = SourceSpan(
            file: "shell.kdl",
            start: SourcePosition(offset: 100, line: 3, column: 10),
            end: SourcePosition(offset: 130, line: 5, column: 4)
        )
        guard case .failure(let wide) = ExpressionParser.parseExpression("a = b", span: multiline) else {
            Issue.record("expected a diagnostic")
            return
        }
        #expect(wide.span == multiline)
    }
}
