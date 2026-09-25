import Testing
@testable import ApolloStyle

private func points(_ values: Double...) -> CSSValue {
    .lengths(values.map { CSSLength($0, .points) })
}

@Suite("CSS: Box und Layout")
struct CSSBoxPropertiesTests {
    private func parse(_ property: String, _ text: String) throws -> CSSValue {
        try CSSPropertyRegistry.parse(property, text, context: CSSParseContext())
    }

    @Test("gültige Werte",
          arguments: [
              ("width", "44px", CSSValue.length(CSSLength(44, .points))),
              ("height", "100%", .length(CSSLength(100, .percent))),
              ("min-width", "auto", .length(CSSLength(0, .auto))),
              ("min-height", "0", .length(CSSLength(0, .points))),
              ("max-width", "none", .length(CSSLength(0, .auto))),
              ("max-height", "320px", .length(CSSLength(320, .points))),
              ("aspect-ratio", "16 / 9", .number(16.0 / 9.0)),
              ("aspect-ratio", "1.5", .number(1.5)),
              ("aspect-ratio", "auto", .keyword("auto")),
              ("padding", "10px 0", points(10, 0, 10, 0)),
              ("padding", "1px 2px 3px", points(1, 2, 3, 2)),
              ("margin", "-4px", points(-4, -4, -4, -4)),
              ("margin", "1px 2px 3px 4px", points(1, 2, 3, 4)),
              ("padding-top", "4px", .length(CSSLength(4, .points))),
              ("padding-right", "10%", .length(CSSLength(10, .percent))),
              ("padding-bottom", "0", .length(CSSLength(0, .points))),
              ("padding-left", "calc(2px * 3)", .length(CSSLength(6, .points))),
              ("margin-top", "-4px", .length(CSSLength(-4, .points))),
              ("margin-right", "2px", .length(CSSLength(2, .points))),
              ("margin-bottom", "5%", .length(CSSLength(5, .percent))),
              ("margin-left", "8px", .length(CSSLength(8, .points))),
              ("gap", "8px", .length(CSSLength(8, .points))),
              ("row-gap", "calc(4px * 2)", .length(CSSLength(8, .points))),
              ("column-gap", "0", .length(CSSLength(0, .points))),
              ("flex-grow", "1", .number(1)),
              ("flex-shrink", "0", .number(0)),
              ("align-items", "center", .keyword("center")),
              ("align-items", "flex-start", .keyword("start")),
              ("align-self", "auto", .keyword("auto")),
              ("align-self", "stretch", .keyword("stretch")),
              ("justify-content", "space-between", .keyword("space-between")),
              ("justify-content", "space-evenly", .keyword("space-evenly")),
              ("grid-template-columns", "repeat(3, 1fr)", .gridColumns(Array(repeating: CSSLength(1, .fraction), count: 3))),
              ("grid-template-columns", "100px 1fr auto 20%", .gridColumns([CSSLength(100, .points), CSSLength(1, .fraction), CSSLength(0, .auto), CSSLength(20, .percent)])),
              ("grid-auto-rows", "64px", .length(CSSLength(64, .points))),
              ("grid-column", "span 2", .span(2)),
              ("grid-row", "span 1", .span(1)),
              ("overflow", "hidden", .keyword("hidden")),
              ("overflow", "visible", .keyword("visible")),
              ("z-index", "3", .number(3)),
              ("z-index", "-1", .number(-1)),
              ("pointer-events", "none", .keyword("none")),
              ("cursor", "pointer", .keyword("pointer")),
              ("cursor", "grab", .keyword("grab")),
          ])
    func valid(property: String, text: String, expected: CSSValue) throws {
        #expect(try parse(property, text) == expected)
    }

    @Test("ungültige Werte",
          arguments: [
              ("width", "-1px"), ("width", "red"), ("width", "1fr"), ("width", "1px 2px"),
              ("aspect-ratio", "0 / 1"), ("aspect-ratio", "16 /"),
              ("padding", "1px 2px 3px 4px 5px"), ("padding", "-1px"),
              ("padding-top", "-1px"), ("padding-left", "1px 2px"), ("margin-bottom", "auto"), ("margin-right", "red"),
              ("gap", "50%"), ("flex-grow", "-1"), ("align-items", "middle"),
              ("justify-content", "stretch"),
              ("grid-template-columns", "repeat(0, 1fr)"), ("grid-template-columns", "1fr 2em"),
              ("grid-column", "2"), ("grid-column", "span 0"),
              ("overflow", "scroll"), ("z-index", "1.5"), ("cursor", "wait"), ("pointer-events", "all"),
          ])
    func invalid(property: String, text: String) {
        #expect(throws: CSSValueError.self) { try parse(property, text) }
    }

    @Test("alle Eigenschaften aus 3.1 sind eingetragen, cursor und pointer-events erben")
    func registry() {
        let names = ["width", "height", "min-width", "max-width", "min-height", "max-height", "aspect-ratio",
                     "padding", "margin", "padding-top", "padding-right", "padding-bottom", "padding-left",
                     "margin-top", "margin-right", "margin-bottom", "margin-left", "gap", "row-gap", "column-gap", "flex-grow", "flex-shrink",
                     "align-items", "align-self", "justify-content", "grid-template-columns", "grid-auto-rows",
                     "grid-column", "grid-row", "overflow", "z-index", "pointer-events", "cursor"]
        for name in names {
            #expect(CSSPropertyRegistry.builtin[name]?.feature == "core", "\(name)")
        }
        #expect(CSSPropertyRegistry.builtin["cursor"]?.inherits == true)
        #expect(CSSPropertyRegistry.builtin["pointer-events"]?.inherits == true)
        #expect(CSSPropertyRegistry.builtin["width"]?.inherits == false)
    }

    @Test("unbekannte Eigenschaft und leerer Wert werden abgelehnt")
    func unknown() {
        #expect(throws: CSSValueError.self) { try parse("colour", "red") }
        #expect(throws: CSSValueError.self) { try parse("width", "  ") }
    }
}
