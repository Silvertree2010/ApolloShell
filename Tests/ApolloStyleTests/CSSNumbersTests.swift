import ApolloShellCore
import Testing
@testable import ApolloStyle

@Suite("CSS: Zahlen, Längen und calc()")
struct CSSNumbersTests {
    private func component(_ text: String) -> CSSComponent {
        CSSList.words(CSSComponentParser.parse(text: text))[0]
    }

    @Test("Funktionen und Klammern werden verschachtelt, Text bleibt erhalten")
    func components() {
        let parsed = CSSComponentParser.parse(text: "glass(regular, rgb(1 2 3)) (a)")
        #expect(parsed.count == 3)
        #expect(parsed[0].functionName == "glass")
        guard case let .function(_, arguments, _) = parsed[0] else {
            Issue.record("keine Funktion")
            return
        }
        #expect(CSSList.commaSeparated(arguments).count == 2)
        #expect(CSSList.text(parsed) == "glass(regular, rgb(1 2 3)) (a)")
    }

    @Test("Längen",
          arguments: [
              ("12px", CSSLength(12, .points)),
              ("12pt", CSSLength(12, .points)),
              ("0", CSSLength(0, .points)),
              ("-4px", CSSLength(-4, .points)),
              ("50%", CSSLength(50, .percent)),
              ("auto", CSSLength(0, .auto)),
          ])
    func lengths(text: String, expected: CSSLength) throws {
        #expect(try CSSRead.length(component(text), percent: true, auto: true) == expected)
    }

    @Test("keine Länge", arguments: ["12", "1em", "red", "12deg", "1fr"])
    func notLengths(text: String) {
        #expect(throws: CSSValueError.self) { try CSSRead.length(component(text), percent: true, auto: true) }
    }

    @Test("Prozent und auto nur, wo erlaubt; negativ nur, wo erlaubt")
    func restrictions() {
        #expect(throws: CSSValueError.self) { try CSSRead.length(component("50%")) }
        #expect(throws: CSSValueError.self) { try CSSRead.length(component("auto")) }
        #expect(throws: CSSValueError.self) { try CSSRead.length(component("-1px"), negative: false) }
    }

    @Test("Winkel, Dauern, Zahlen, Anteile")
    func otherUnits() throws {
        #expect(try CSSRead.angle(component("-90deg")) == -90)
        #expect(try CSSRead.duration(component("200ms")) == 0.2)
        #expect(try CSSRead.duration(component("1.5s")) == 1.5)
        #expect(try CSSRead.duration(component("0")) == 0)
        #expect(try CSSRead.number(component("2.5")) == 2.5)
        #expect(try CSSRead.ratio(component("40%")) == 0.4)
        #expect(try CSSRead.ratio(component("1.4")) == 1)
        #expect(try CSSRead.integer(component("3"), in: 1...64) == 3)
        #expect(throws: CSSValueError.self) { try CSSRead.integer(component("2.5"), in: 1...64) }
        #expect(throws: CSSValueError.self) { try CSSRead.number(component("-1"), minimum: 0) }
    }

    @Test("calc() rechnet mit Vorrang, Klammern und verschachtelt",
          arguments: [
              ("calc(10px + 2px * 3)", CSSNumeric(value: 16, dimension: .length)),
              ("calc((10px + 2px) * 3)", CSSNumeric(value: 36, dimension: .length)),
              ("calc(100% / 4)", CSSNumeric(value: 25, dimension: .percent)),
              ("calc(2 * 3)", CSSNumeric(value: 6, dimension: .number)),
              ("calc(3 * -0.07s)", CSSNumeric(value: -0.21000000000000002, dimension: .duration)),
              ("calc(calc(4px * 2) - 1px)", CSSNumeric(value: 7, dimension: .length)),
              ("calc(90deg / 2)", CSSNumeric(value: 45, dimension: .angle)),
          ])
    func calc(text: String, expected: CSSNumeric) throws {
        #expect(try CSSNumbers.numeric(component(text)) == expected)
    }

    @Test("calc() lehnt Unsinn mit Meldung ab",
          arguments: ["calc(10px + 5%)", "calc(1px / 0)", "calc(2px * 3px)", "calc(1px / 2px)", "calc(10px -5px)", "calc()", "calc(red)"])
    func calcErrors(text: String) {
        #expect(throws: CSSValueError.self) { try CSSNumbers.numeric(component(text)) }
    }

    @Test("calc() liefert Längen für Längenstellen")
    func calcAsLength() throws {
        #expect(try CSSRead.length(component("calc(44px - 2px * 2)")) == CSSLength(40, .points))
    }

    @Test("min(), max() und clamp() wählen unter Längen, auch mit calc() darin",
          arguments: [
              ("min(26px, 20px)", CSSNumeric(value: 20, dimension: .length)),
              ("max(10px, 4px, 7px)", CSSNumeric(value: 10, dimension: .length)),
              ("clamp(10px, 4px, 30px)", CSSNumeric(value: 10, dimension: .length)),
              ("clamp(10px, 50px, 30px)", CSSNumeric(value: 30, dimension: .length)),
              ("clamp(10px, 20px, 30px)", CSSNumeric(value: 20, dimension: .length)),
              ("min(26px, max(28px - 4px, 0px))", CSSNumeric(value: 24, dimension: .length)),
              ("calc(min(4px, 9px) * 2)", CSSNumeric(value: 8, dimension: .length)),
              ("max(10%, 20%)", CSSNumeric(value: 20, dimension: .percent)),
          ])
    func minMax(text: String, expected: CSSNumeric) throws {
        #expect(try CSSNumbers.numeric(component(text)) == expected)
    }

    @Test("min(), max() und clamp() lehnen Unsinn ab",
          arguments: ["min()", "min(1px,)", "max(1px, 2)", "clamp(1px, 2px)", "clamp(1px, 2px, 3px, 4px)", "min(red, 1px)", "max(1px 2px)"])
    func minMaxErrors(text: String) {
        #expect(throws: CSSValueError.self) { try CSSNumbers.numeric(component(text)) }
    }

    @Test("min() liefert Längen für Längenstellen")
    func minAsLength() throws {
        #expect(try CSSRead.length(component("min(26px, 18px)")) == CSSLength(18, .points))
    }

    @Test("Schlüsselwörter mit Aliassen")
    func keywords() throws {
        #expect(try CSSRead.keyword(component("Center"), ["start", "center", "end"]) == "center")
        #expect(try CSSRead.keyword(component("flex-end"), ["start", "end"], aliases: ["flex-end": "end"]) == "end")
        #expect(throws: CSSValueError.self) { try CSSRead.keyword(component("middle"), ["start", "end"]) }
    }

    @Test("genau ein Wert")
    func single() {
        #expect(throws: CSSValueError.self) { try CSSRead.single(CSSComponentParser.parse(text: "1px 2px")) }
        #expect(throws: CSSValueError.self) { try CSSRead.single(CSSComponentParser.parse(text: "  ")) }
    }

    @Test("tief verschachtelte Klammern erzeugen kein Sprengen des Stacks")
    func deepParentheses() {
        let depth = 20000
        let text = String(repeating: "(", count: depth) + "a" + String(repeating: ")", count: depth)
        let parsed = CSSComponentParser.parse(text: text)
        #expect(CSSList.text(parsed) == text)
    }

    @Test("tief verschachteltes calc() meldet eine Grenze statt abzustürzen")
    func deepCalc() {
        let depth = 5000
        let text = "calc(" + String(repeating: "(1px + ", count: depth) + "1px" + String(repeating: ")", count: depth) + ")"
        #expect(throws: CSSValueError.self) { try CSSNumbers.numeric(component(text)) }
    }
}
