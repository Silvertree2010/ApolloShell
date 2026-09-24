import Testing
@testable import ApolloConfig

@Suite("Lexer für Ausdrücke")
struct ExpressionLexerTests {
    static func kinds(_ source: String) throws -> [ExpressionTokenKind] {
        try ExpressionLexer.scan(Array(source)).map(\.kind)
    }

    static func failure(_ source: String) -> ExpressionSyntaxError? {
        do throws(ExpressionSyntaxError) {
            _ = try ExpressionLexer.scan(Array(source))
            return nil
        } catch {
            return error
        }
    }

    @Test("kebab-case: Bindestrich zwischen Namenszeichen gehört zum Namen", arguments: [
        ("app.bundle-id", [ExpressionTokenKind.name("app"), .symbol("."), .name("bundle-id"), .end]),
        ("a-b", [.name("a-b"), .end]),
        ("a - b", [.name("a"), .symbol("-"), .name("b"), .end]),
        ("a -b", [.name("a"), .symbol("-"), .name("b"), .end]),
        ("a- b", [.name("a"), .symbol("-"), .name("b"), .end]),
        ("a--b", [.name("a"), .symbol("-"), .symbol("-"), .name("b"), .end]),
        ("x-1", [.name("x-1"), .end]),
        ("_tmp2", [.name("_tmp2"), .end]),
        ("1-2", [.number(1), .symbol("-"), .number(2), .end]),
    ])
    func kebabNames(source: String, expected: [ExpressionTokenKind]) throws {
        #expect(try Self.kinds(source) == expected)
    }

    @Test("Zahlen, Strings und Operatoren", arguments: [
        ("1.5 2", [ExpressionTokenKind.number(1.5), .number(2), .end]),
        ("1.", [.number(1), .symbol("."), .end]),
        ("'it\\'s \\\\ ok'", [.string("it's \\ ok"), .end]),
        ("'a}b'", [.string("a}b"), .end]),
        ("''", [.string(""), .end]),
        ("a ?? b ? c : d", [.name("a"), .symbol("??"), .name("b"), .symbol("?"), .name("c"), .symbol(":"), .name("d"), .end]),
        ("<= >= == != || && < > ! % * /", [.symbol("<="), .symbol(">="), .symbol("=="), .symbol("!="), .symbol("||"), .symbol("&&"), .symbol("<"), .symbol(">"), .symbol("!"), .symbol("%"), .symbol("*"), .symbol("/"), .end]),
        ("x | f [1, 2](y)", [.name("x"), .symbol("|"), .name("f"), .symbol("["), .number(1), .symbol(","), .number(2), .symbol("]"), .symbol("("), .name("y"), .symbol(")"), .end]),
        ("\t a \n", [.name("a"), .end]),
    ])
    func tokens(source: String, expected: [ExpressionTokenKind]) throws {
        #expect(try Self.kinds(source) == expected)
    }

    @Test("Positionen zählen Zeichen, nicht Bytes")
    func positions() throws {
        let tokens = try ExpressionLexer.scan(Array("ab + 'ä'"))
        #expect(tokens.map(\.start) == [0, 3, 5, 8])
        #expect(tokens.map(\.end) == [2, 4, 8, 8])
    }

    @Test("Fehler mit Text und Hilfe", arguments: [
        ("a = b", "unexpected '='", "use '==' to compare values"),
        ("a & b", "unexpected '&'", "use '&&' for 'and'"),
        ("\"x\"", "strings in expressions use single quotes", "write 'text' instead of \"text\""),
        ("'abc", "unterminated string", "close the string with a single quote"),
        ("'a\\n'", "invalid escape '\\n' in string", "only \\' and \\\\ are escapes in expression strings"),
        ("Foo", "unexpected character 'F'", "names are lowercase kebab-case"),
        ("a # b", "unexpected character '#'", nil),
        ("a { b", "unexpected '{'", "expressions cannot contain braces; write '{{' or '}}' outside an expression for a literal brace"),
        ("ä", "unexpected character 'ä'", nil),
    ] as [(String, String, String?)])
    func errors(source: String, message: String, help: String?) {
        let error = Self.failure(source)
        #expect(error?.message == message)
        #expect(error?.help == help)
    }

    @Test("Fehlerstelle zeigt auf das Zeichen")
    func errorPosition() {
        let error = Self.failure("ab = c")
        #expect(error?.start == 3)
        #expect(error?.end == 4)
    }

    @Test("Mehr als 512 Token sind ein Fehler, 512 gehen")
    func tokenLimit() throws {
        let allowed = Array(repeating: "a", count: 256).joined(separator: " + ")
        #expect(try ExpressionLexer.scan(Array(allowed)).count == 512)
        let tooLong = Array(repeating: "a", count: 300).joined(separator: " + ")
        #expect(Self.failure(tooLong)?.message == "expression is too long")
    }

    @Test("Eine Zahl, die nicht endlich ist, ist ein Fehler")
    func hugeNumber() {
        let source = "1" + String(repeating: "0", count: 400)
        #expect(Self.failure(source)?.message == "number is too large")
    }
}
