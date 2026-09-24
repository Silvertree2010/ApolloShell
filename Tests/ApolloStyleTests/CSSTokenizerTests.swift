import ApolloBase
import Testing
@testable import ApolloStyle

@Suite("CSS: Tokenizer")
struct CSSTokenizerTests {
    private func kinds(_ text: String) -> [CSSTokenKind] {
        CSSTokenizer.tokenize(text).tokens.map(\.kind).filter { $0 != .whitespace }
    }

    @Test("Namen, Funktionen, Zahlen und Einheiten")
    func basics() {
        #expect(kinds("width: 12px 50% 1.5 -90deg 200MS") == [
            .ident("width"), .colon, .dimension(12, "px"), .percentage(50), .number(1.5),
            .dimension(-90, "deg"), .dimension(200, "ms"),
        ])
        #expect(kinds("rgb(1, 2)") == [.function("rgb"), .number(1), .comma, .number(2), .closeParen])
        #expect(kinds("#sidebar .icon") == [.hash("sidebar"), .delim("."), .ident("icon")])
        #expect(kinds("@media") == [.atKeyword("media")])
        #expect(kinds(".5 +3 1e2") == [.number(0.5), .number(3), .number(100)])
    }

    @Test("Systemfarben und Custom Properties sind Namen")
    func dashedIdents() {
        #expect(kinds("-apple-system-label --my-size") == [.ident("-apple-system-label"), .ident("--my-size")])
    }

    @Test("Minus mit Leerraum ist ein Operator, ohne Leerraum Teil der Zahl")
    func minus() {
        #expect(kinds("10px - 5px") == [.dimension(10, "px"), .delim("-"), .dimension(5, "px")])
        #expect(kinds("10px -5px") == [.dimension(10, "px"), .dimension(-5, "px")])
    }

    @Test("Zeichenketten mit Escapes, url() mit und ohne Anführungszeichen")
    func stringsAndURLs() {
        #expect(kinds(#""a\"b" 'c'"#) == [.string("a\"b"), .string("c")])
        #expect(kinds("url(img/a.png)") == [.url("img/a.png")])
        #expect(kinds("url( \"b.png\" )") == [.function("url"), .string("b.png"), .closeParen])
        #expect(kinds("url(a b)") == [.badURL])
        #expect(kinds(#"\31 23"#) == [.ident("123")])
    }

    @Test("Kommentare zählen als Leerraum")
    func comments() {
        #expect(kinds("a/* x */b") == [.ident("a"), .ident("b")])
        #expect(CSSTokenizer.tokenize("a/**/b").tokens.map(\.kind) == [.ident("a"), .whitespace, .ident("b")])
    }

    @Test("Positionen: Zeile, Spalte in Zeichen, Offset in Bytes, CRLF und Tabs")
    func positions() {
        let text = "a {\r\n\tcolor: red;\n}\n/* ä 😀 */ b"
        let tokens = CSSTokenizer.tokenize(text).tokens.filter { $0.kind != .whitespace }
        let color = tokens.first { $0.kind == .ident("color") }
        #expect(color?.start.line == 2)
        #expect(color?.start.column == 2)
        #expect(color?.start.offset == 6)
        let last = tokens.last
        #expect(last?.kind == .ident("b"))
        #expect(last?.start.line == 4)
        #expect(last?.start.column == 11)
        #expect(last?.start.offset == Array("a {\r\n\tcolor: red;\n}\n/* ä 😀 */ ".utf8).count)
    }

    @Test("offene Zeichenketten und Kommentare werden gemeldet, ohne Absturz")
    func problems() {
        let string = CSSTokenizer.tokenize("a: \"offen\nb")
        #expect(string.problems.map(\.message) == ["unterminated string"])
        #expect(string.problems.first?.position.line == 1)
        let comment = CSSTokenizer.tokenize("a /* offen")
        #expect(comment.problems.map(\.message) == ["unterminated comment"])
    }

    @Test("zufällige Bytes ergeben Token, nie einen Absturz")
    func garbage() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let scalars = (0..<200).compactMap { _ in Unicode.Scalar(UInt32.random(in: 0...0x2FF, using: &generator)) }
            let text = String(String.UnicodeScalarView(scalars))
            let result = CSSTokenizer.tokenize(text)
            #expect(result.tokens.map(\.text).joined() == text)
        }
    }
}
