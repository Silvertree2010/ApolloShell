import Testing
@testable import ApolloStyle

@Suite("CSS: Selektoren")
struct CSSSelectorTests {
    private func selectors(_ text: String) -> (selectors: [ComplexSelector], problems: [String]) {
        SelectorParser.parse(CSSComponentParser.parse(text: text))
    }

    private func selector(_ text: String) throws -> ComplexSelector {
        let parsed = selectors(text)
        #expect(parsed.problems.isEmpty, "\(parsed.problems)")
        return try #require(parsed.selectors.first)
    }

    @Test("Spezifität",
          arguments: [
              ("button", Specificity(ids: 0, classes: 0, types: 1)),
              (".a", Specificity(ids: 0, classes: 1, types: 0)),
              ("#x", Specificity(ids: 1, classes: 0, types: 0)),
              ("button.primary:hover", Specificity(ids: 0, classes: 2, types: 1)),
              ("#sidebar .sidebar-icon", Specificity(ids: 1, classes: 1, types: 0)),
              ("row > text", Specificity(ids: 0, classes: 0, types: 2)),
              ("*", Specificity(ids: 0, classes: 0, types: 0)),
              (":root", Specificity(ids: 0, classes: 1, types: 0)),
          ])
    func specificity(text: String, expected: Specificity) throws {
        #expect(try selector(text).specificity == expected)
    }

    @Test("Spezifität vergleicht Kennungen vor Klassen vor Typen")
    func ordering() {
        #expect(Specificity(ids: 0, classes: 9, types: 9) < Specificity(ids: 1, classes: 0, types: 0))
        #expect(Specificity(ids: 0, classes: 1, types: 0) > Specificity(ids: 0, classes: 0, types: 5))
    }

    @Test("einfache und zusammengesetzte Selektoren")
    func simple() throws {
        let button = StyleSubject(kind: "button", id: "go", classes: ["primary", "big"], pseudo: [.hover])
        #expect(try selector("button").matches(button, ancestors: []))
        #expect(try selector("BUTTON").matches(button, ancestors: []))
        #expect(try selector(".primary").matches(button, ancestors: []))
        #expect(try selector("#go").matches(button, ancestors: []))
        #expect(try selector("*").matches(button, ancestors: []))
        #expect(try selector("button.primary.big:hover").matches(button, ancestors: []))
        #expect(try !selector("button.primary:active").matches(button, ancestors: []))
        #expect(try !selector("#Go").matches(button, ancestors: []))
        #expect(try !selector("text").matches(button, ancestors: []))
    }

    @Test("Nachfahre, Kind und Pseudoklasse am Vorfahren")
    func combinators() throws {
        let panel = StyleSubject(kind: "panel", id: "sidebar", pseudo: [.hover])
        let column = StyleSubject(kind: "column", classes: ["modules"])
        let row = StyleSubject(kind: "row")
        let icon = StyleSubject(kind: "button", classes: ["sidebar-icon"])
        let ancestors = [panel, column, row]
        #expect(try selector("#sidebar .sidebar-icon").matches(icon, ancestors: ancestors))
        #expect(try selector("row > button").matches(icon, ancestors: ancestors))
        #expect(try !selector("column > button").matches(icon, ancestors: ancestors))
        #expect(try selector("panel .modules > row button").matches(icon, ancestors: ancestors))
        #expect(try selector("panel:hover .sidebar-icon").matches(icon, ancestors: ancestors))
        #expect(try !selector("panel:active .sidebar-icon").matches(icon, ancestors: ancestors))
        #expect(try !selector("#sidebar > .sidebar-icon").matches(icon, ancestors: ancestors))
    }

    @Test(":root trifft nur die Wurzel und ist allein ein reiner :root-Selektor")
    func root() throws {
        let surface = StyleSubject(kind: "panel", id: "sidebar")
        let child = StyleSubject(kind: "text")
        #expect(try selector(":root").matches(surface, ancestors: []))
        #expect(try !selector(":root").matches(child, ancestors: [surface]))
        #expect(try selector(":root text").matches(child, ancestors: [surface]))
        #expect(try selector(":root").isBareRoot)
        #expect(try !selector(":root text").isBareRoot)
        #expect(try !selector("panel:root").isBareRoot)
    }

    @Test("jede Pseudoklasse aus der Spec wird erkannt",
          arguments: ["hover", "active", "focus", "checked", "disabled", "open", "first-child", "last-child", "invalid", "overflowing"])
    func pseudoClasses(name: String) throws {
        let state = try #require(PseudoState.byName[name])
        #expect(try selector(":\(name)").matches(StyleSubject(kind: "x", pseudo: state), ancestors: []))
        #expect(try !selector(":\(name)").matches(StyleSubject(kind: "x"), ancestors: []))
    }

    @Test("nicht unterstützte Selektoren fallen mit Meldung weg, der Rest der Liste bleibt",
          arguments: ["a + b", "a ~ b", "[x]", "a[x=y]", ":nth-child(2)", ":has(.a)", ":not(.a)", "::before", ":foo",
                      "> a", "a >", "a > > b", ".", "a b.", "a*"])
    func unsupported(text: String) {
        let parsed = selectors(".keep, \(text)")
        #expect(parsed.selectors.count == 1)
        #expect(parsed.problems.count == 1)
    }

    @Test("Liste mit mehreren Selektoren, Kennung nach Typ ist erlaubt")
    func list() {
        let parsed = selectors(".a, .b , text, #x text#y")
        #expect(parsed.selectors.count == 4)
        #expect(parsed.problems.isEmpty)
    }
}
