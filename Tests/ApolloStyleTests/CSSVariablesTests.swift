import ApolloShellCore
import Testing
@testable import ApolloStyle

@Suite("CSS: var() und Custom Properties")
struct CSSVariablesTests {
    private func substitute(_ text: String, _ values: [String: String]) throws -> String {
        try CSSVariables.substitute(text) { values[$0] }
    }

    @Test("gesetzte Werte werden eingesetzt, sonst gilt der Ersatz")
    func fallback() throws {
        #expect(try substitute("var(--a, 8px)", ["--a": "4px"]) == "4px")
        #expect(try substitute("var(--a, 8px)", [:]) == " 8px")
        #expect(try substitute("var(--a, var(--b, 1px 2px))", ["--b": "3px"]) == " 3px")
        #expect(try substitute("glass(regular, var(--tint, red))", [:]) == "glass(regular,  red)")
        #expect(try substitute("calc(var(--a) * 2)", ["--a": "5px"]) == "calc(5px * 2)")
    }

    @Test("ohne Wert und ohne Ersatz ist die Deklaration ungültig")
    func missing() {
        #expect(throws: CSSValueError.self) { try substitute("var(--nope)", [:]) }
        #expect(throws: CSSValueError.self) { try substitute("var(nope, 1px)", [:]) }
    }

    @Test("zu tiefe Verschachtelung wird abgelehnt")
    func depth() {
        var text = "1px"
        for _ in 0..<40 { text = "var(--x, \(text))" }
        #expect(throws: CSSValueError.self) { try substitute(text, [:]) }
    }

    @Test("Token nicht gesetzt: Ersatz; Theme setzt es: Themewert; Verlauf none: Ersatz")
    func themeTokens() throws {
        func tokens(_ css: String) -> TokenEnvironment {
            ThemeTokenBridge.environment(
                for: Theme.make(identifier: "t", styleSheet: ThemeStyleSheetParser.parse(css)), appearance: .light)
        }
        let resolver = CustomPropertyResolver(own: [:], inherited: [:], tokens: tokens(":root { --apollo-bar-color: #102030; --apollo-bar-gradient: none; }"))
        #expect(try CSSVariables.substitute("var(--apollo-bar-color, red)") { resolver.value($0) } == "#102030")
        #expect(try CSSVariables.substitute("var(--apollo-bar-gradient, red)") { resolver.value($0) } == " red")
        #expect(try CSSVariables.substitute("var(--apollo-panel-color, blue)") { resolver.value($0) } == " blue")
    }

    @Test("eigene Werte schlagen geerbte und dürfen auf geerbte verweisen")
    func ownAndInherited() {
        let resolver = CustomPropertyResolver(
            own: ["--gap": "calc(var(--base) * 2)", "--base": "3px"],
            inherited: ["--base": "1px", "--color": "red"],
            tokens: .empty)
        #expect(resolver.resolveAll() == ["--gap": "calc(3px * 2)", "--base": "3px", "--color": "red"])
        #expect(resolver.failures.isEmpty)
    }

    @Test("ein Zyklus macht beide Werte ungültig, ohne Endlosschleife")
    func cycle() {
        let resolver = CustomPropertyResolver(own: ["--a": "var(--b)", "--b": "var(--a)"], inherited: ["--a": "9px"], tokens: .empty)
        let result = resolver.resolveAll()
        #expect(result["--a"] == nil)
        #expect(result["--b"] == nil)
        #expect(Set(resolver.failures.map(\.name)) == ["--a", "--b"])
    }

    @Test("Custom Properties lesen Tokens, setzen sie aber nicht")
    func tokenLookup() {
        let tokens = TokenEnvironment(values: ["--apollo-spacing": "12px"])
        let resolver = CustomPropertyResolver(own: ["--pad": "var(--apollo-spacing)"], inherited: [:], tokens: tokens)
        #expect(resolver.resolveAll() == ["--pad": "12px"])
    }

    @Test("containsVar erkennt var() unabhängig von Gross- und Kleinschreibung")
    func detection() {
        #expect(CSSVariables.containsVar("1px VAR(--a)"))
        #expect(!CSSVariables.containsVar("1px variant"))
    }
}
