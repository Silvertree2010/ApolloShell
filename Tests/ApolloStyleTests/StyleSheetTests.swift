import ApolloBase
import Testing
@testable import ApolloStyle

@Suite("CSS: Stylesheets lesen")
struct StyleSheetTests {
    private func parse(_ text: String, origin: StyleOrigin = .config) -> (StyleSheet, [Diagnostic]) {
        StyleSheet.parse(text, file: "style.css", origin: origin)
    }

    private func environment(_ appearance: Appearance, motion: Bool = false, transparency: Bool = false,
                             tokens: TokenEnvironment = .empty) -> StyleEnvironment {
        StyleEnvironment(appearance: appearance, reduceMotion: motion, reduceTransparency: transparency, tokens: tokens)
    }

    @Test("Regeln und Deklarationen in Reihenfolge, !important auch mit Leerraum")
    func rules() {
        let (sheet, diagnostics) = parse("""
        #sidebar { width: 44px; height: 100% }
        .a, .b { color: red !important; gap: 2px ! IMPORTANT }
        """)
        #expect(diagnostics.isEmpty)
        #expect(sheet.rules.count == 2)
        #expect(sheet.rules[0].declarations.map(\.property) == ["width", "height"])
        #expect(sheet.rules[0].declarations.map(\.rawValue) == ["44px", "100%"])
        #expect(sheet.rules[1].selectors.count == 2)
        #expect(sheet.rules[1].declarations.map(\.important) == [true, true])
        #expect(sheet.rules[1].declarations.map(\.rawValue) == ["red", "2px"])
        #expect(sheet.origin == .config)
        #expect(sheet.file == "style.css")
    }

    @Test("unbekannte Eigenschaft: Warnung mit Zeile und Vorschlag, der Rest der Regel gilt")
    func unknownProperty() throws {
        let (sheet, diagnostics) = parse("a {\n  colr: red;\n  width: 2px;\n}")
        let warning = try #require(diagnostics.first)
        #expect(diagnostics.count == 1)
        #expect(warning.severity == .warning)
        #expect(warning.message.contains("unknown property 'colr'"))
        #expect(warning.span?.start.line == 2)
        #expect(warning.span?.start.column == 3)
        #expect(warning.help == "did you mean 'color'?")
        #expect(sheet.rules[0].declarations.map(\.property) == ["width"])
    }

    @Test("ungültiger Wert fällt weg; Werte mit var() prüft erst die Kaskade")
    func invalidValue() {
        let (sheet, diagnostics) = parse("a { width: red; height: var(--h); opacity: inherit }")
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.message.contains("invalid value for 'width'") == true)
        #expect(sheet.rules[0].declarations.map(\.property) == ["height", "opacity"])
    }

    @Test("nicht unterstützter Selektor: Warnung mit Zeile, übrige Selektoren gelten")
    func unsupportedSelector() {
        let (sheet, diagnostics) = parse("\n\n.a + .b, .c { width: 1px }")
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.span?.start.line == 3)
        #expect(diagnostics.first?.message.contains("sibling combinators") == true)
        #expect(sheet.rules.first?.selectors.count == 1)
    }

    @Test("@media für Hell und Dunkel, Bewegung und Transparenz")
    func media() {
        let (sheet, diagnostics) = parse("""
        @media (prefers-color-scheme: dark) { a { width: 1px } }
        @media (prefers-reduced-motion: reduce) { a { width: 2px } }
        @media (prefers-reduced-transparency: reduce) and (prefers-color-scheme: light) { a { width: 3px } }
        @media (prefers-color-scheme: light), (prefers-reduced-motion: no-preference) { a { width: 4px } }
        @media all and (prefers-color-scheme: dark) { @media (prefers-reduced-motion: reduce) { a { width: 5px } } }
        """)
        #expect(diagnostics.isEmpty)
        #expect(sheet.rules.count == 5)
        let rules = sheet.rules
        func applies(_ index: Int, _ environment: StyleEnvironment) -> Bool {
            rules[index].media.allSatisfy { $0.matches(environment) }
        }
        #expect(applies(0, environment(.dark)))
        #expect(!applies(0, environment(.light)))
        #expect(applies(0, environment(.light, tokens: TokenEnvironment(values: ["--apollo-theme-appearance": "dark"]))))
        #expect(applies(1, environment(.light, motion: true)))
        #expect(!applies(1, environment(.light)))
        #expect(applies(2, environment(.light, transparency: true)))
        #expect(!applies(2, environment(.dark, transparency: true)))
        #expect(applies(3, environment(.dark)))
        #expect(!applies(3, environment(.dark, motion: true)))
        #expect(rules[4].media.count == 2)
        #expect(applies(4, environment(.dark, motion: true)))
        #expect(!applies(4, environment(.dark)))
    }

    @Test("andere At-Regeln und Bedingungen werden mit Warnung übergangen, samt Inhalt",
          arguments: ["@import url(x.css);", "@font-face { font-family: x; }", "@supports (display: grid) { a { width: 1px } }",
                      "@keyframes spin { from { opacity: 0 } }", "@media (min-width: 100px) { a { width: 1px } }",
                      "@media screen { a { width: 1px } }", "@charset \"utf-8\";"])
    func otherAtRules(text: String) {
        let (sheet, diagnostics) = parse(text)
        #expect(sheet.rules.isEmpty)
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.severity == .warning)
    }

    @Test("--apollo-* darf kein Stylesheet setzen, eigene Namen schon", arguments: [StyleOrigin.base, .config, .user])
    func themeTokensAreReadOnly(origin: StyleOrigin) {
        let (sheet, diagnostics) = parse(":root { --apollo-bar-color: red; --Sidebar-Size: 32px; } .x { --local: 1px; }", origin: origin)
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.message.contains("--apollo-bar-color") == true)
        #expect(sheet.declaredCustomProperties == ["--Sidebar-Size"])
        #expect(sheet.rules[0].declarations.map(\.property) == ["--Sidebar-Size"])
    }

    @Test("verschachtelte Regeln und Streutext werden gemeldet, der Rest gilt")
    func nestedAndStray() {
        let (sheet, diagnostics) = parse("a { b { width: 1px } height: 2px; width: 3px }\n} color: red;")
        #expect(sheet.rules.first?.declarations.map(\.rawValue) == ["3px"])
        #expect(diagnostics.count == 2)
        #expect(diagnostics.first?.message.contains("nested rules") == true)
        #expect(diagnostics.last?.span?.start.line == 2)
    }

    @Test("Zeilen und Spalten stimmen nach Emoji, Umlauten und CRLF")
    func positions() {
        let (_, diagnostics) = parse("/* 😀 ä */\r\n.grün {\r\n  colr: red;\r\n}")
        #expect(diagnostics.first?.span?.start.line == 3)
        #expect(diagnostics.first?.span?.start.column == 3)
    }

    @Test("offene Zeichenkette wird gemeldet")
    func unterminatedString() {
        let (_, diagnostics) = parse("a { font-family: \"offen\n}")
        #expect(diagnostics.contains { $0.message == "unterminated string" && $0.span?.start.line == 1 })
    }

    @Test("zu grosse Datei ist ein Fehler, eine Datei an der Grenze wird gelesen")
    func sizeLimit() {
        let (large, largeDiagnostics) = parse(String(repeating: "a", count: StyleSheet.maximumBytes + 1))
        #expect(large.rules.isEmpty)
        #expect(largeDiagnostics.count == 1)
        #expect(largeDiagnostics.first?.severity == .error)
        let atLimit = "/*" + String(repeating: " ", count: StyleSheet.maximumBytes - 4) + "*/"
        #expect(parse(atLimit).1.isEmpty)
    }

    @Test("mehr als 8192 Regeln: die ersten gelten, eine Warnung")
    func ruleLimit() {
        let text = (0..<8193).map { ".r\($0) { width: 1px }" }.joined(separator: "\n")
        let (sheet, diagnostics) = parse(text)
        #expect(sheet.rules.count == 8192)
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.message.contains("8192") == true)
    }

    @Test("höchstens 200 Diagnosen, die letzte nennt den Rest")
    func diagnosticLimit() {
        let text = "a { " + (0..<300).map { "x\($0): 1;" }.joined() + " }"
        let (_, diagnostics) = parse(text)
        #expect(diagnostics.count == 200)
        #expect(diagnostics.last?.severity == .note)
        #expect(diagnostics.last?.message.contains("101 more") == true)
    }

    @Test("Zufallstext: kein Absturz, höchstens 200 Diagnosen")
    func garbage() {
        var generator = SystemRandomNumberGenerator()
        let alphabet = Array("{}();:,.#@!*>+~[]\"'/\\ \n\tabcxyz-_0123456789%")
        for _ in 0..<50 {
            let text = String((0..<5000).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] })
            let (_, diagnostics) = parse(text)
            #expect(diagnostics.count <= 200)
        }
    }

    @Test("leere Datei ergibt nichts")
    func empty() {
        let (sheet, diagnostics) = parse("")
        #expect(sheet.rules.isEmpty)
        #expect(diagnostics.isEmpty)
    }

    @Test("url() ohne Wurzelordner wird mit Warnung abgelehnt")
    func urlWithoutRoot() {
        let (sheet, diagnostics) = parse("a { background: url(bg.png) }")
        #expect(sheet.rules[0].declarations.isEmpty)
        #expect(diagnostics.first?.message.contains("needs a config or package folder") == true)
    }

    @Test("Verschachtelung tiefer als 256 wird mit Ort gemeldet, keine stille Kappung")
    func excessiveNesting() {
        let opens = String(repeating: "b { ", count: 260)
        let closes = String(repeating: " }", count: 260)
        let text = "a { " + opens + "width: 1px" + closes + " }"
        let (_, diagnostics) = parse(text)
        let warning = diagnostics.first { $0.message.contains("256") }
        #expect(warning != nil)
        #expect(warning?.severity == .warning)
        #expect(warning?.span?.start.line == 1)
    }
}
