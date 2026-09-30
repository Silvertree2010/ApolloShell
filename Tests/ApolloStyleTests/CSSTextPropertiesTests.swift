import ApolloShellCore
import Testing
@testable import ApolloStyle

@Suite("CSS: Schrift, Symbole, Anzeigen")
struct CSSTextPropertiesTests {
    private func parse(_ property: String, _ text: String) throws -> CSSValue {
        try CSSPropertyRegistry.parse(property, text, context: CSSParseContext())
    }

    @Test("gültige Werte",
          arguments: [
              ("font-family", "ui-rounded", CSSValue.fontFamilies(["ui-rounded"])),
              ("font-family", "\"SF Pro Display\", System-UI", .fontFamilies(["SF Pro Display", "system-ui"])),
              ("font-family", "Helvetica Neue, ui-monospace", .fontFamilies(["Helvetica Neue", "ui-monospace"])),
              ("font-size", "13px", .length(CSSLength(13, .points))),
              ("font-weight", "600", .number(600)),
              ("font-weight", "bold", .number(700)),
              ("font-weight", "normal", .number(400)),
              ("font-style", "italic", .keyword("italic")),
              ("font-variant-numeric", "tabular-nums", .keyword("tabular-nums")),
              ("line-height", "1.2", .number(1.2)),
              ("line-height", "18px", .length(CSSLength(18, .points))),
              ("line-height", "normal", .keyword("normal")),
              ("letter-spacing", "-0.5px", .length(CSSLength(-0.5, .points))),
              ("letter-spacing", "normal", .length(CSSLength(0, .points))),
              ("text-align", "center", .keyword("center")),
              ("text-align", "left", .keyword("start")),
              ("text-align", "right", .keyword("end")),
              ("-apollo-font-scale", "none", .keyword("none")),
              ("-apollo-image-rendering", "template", .keyword("template")),
              ("-apollo-symbol-rendering", "multicolor", .keyword("multicolor")),
              ("-apollo-symbol-rendering", "hierarchical", .keyword("hierarchical")),
              ("-apollo-symbol-effect", "variable-color", .keyword("variable-color")),
              ("-apollo-symbol-effect", "bounce", .keyword("bounce")),
              ("-apollo-content-transition", "numeric", .keyword("numeric")),
              ("-apollo-content-transition", "symbol", .keyword("symbol")),
              ("-apollo-track-color", "rgb(from -apple-system-label r g b / 0.1)", .color(.system(name: "-apple-system-label", alpha: 0.1))),
              ("-apollo-fill-color", "-apple-system-control-accent", .layers([.color(.system(name: "-apple-system-control-accent", alpha: 1))])),
              ("-apollo-fill", "linear-gradient(red, blue)", .layers([.gradient(LinearGradient(angleDegrees: 180, stops: [
                  GradientStop(color: .rgba(red: 1, green: 0, blue: 0, alpha: 1), position: 0),
                  GradientStop(color: .rgba(red: 0, green: 0, blue: 1, alpha: 1), position: 1),
              ]))])),
              ("-apollo-thumb-color", "white", .color(.rgba(red: 1, green: 1, blue: 1, alpha: 1))),
              ("-apollo-thumb-size", "20px", .lengths([CSSLength(20, .points), CSSLength(20, .points)])),
              ("-apollo-thumb-size", "28px 20px", .lengths([CSSLength(28, .points), CSSLength(20, .points)])),
              ("-apollo-fill-mode", "inside-linear", .keyword("inside-linear")),
              ("-apollo-thumb-shadow", "0 1px 2px rgb(0 0 0 / 20%)", .shadows([Shadow(x: 0, y: 1, blur: 2, spread: 0,
                  color: CSSColorParser.rgba(.init(red: 0, green: 0, blue: 0, alpha: 0.2)))])),
              ("-apollo-sweep-angle", "180deg", .angle(180)),
              ("-apollo-start-angle", "-90deg", .angle(-90)),
              ("-apollo-stroke-width", "4px", .length(CSSLength(4, .points))),
              ("-apollo-stroke-dash", "3px 4px", .lengths([CSSLength(3, .points), CSSLength(4, .points)])),
          ])
    func valid(property: String, text: String, expected: CSSValue) throws {
        #expect(try parse(property, text) == expected)
    }

    @Test("ungültige Werte",
          arguments: [
              ("font-family", "\"\""), ("font-family", "12px"), ("font-family", "a,,b"),
              ("font-size", "0"), ("font-size", "50%"), ("font-weight", "950"), ("font-weight", "heavy"),
              ("font-style", "oblique"), ("font-variant-numeric", "oldstyle-nums"), ("line-height", "-1"),
              ("text-align", "justify"), ("-apollo-font-scale", "half"), ("-apollo-symbol-effect", "wiggle"),
              ("-apollo-fill-color", "material(regular)"), ("-apollo-fill", "red, blue"),
              ("-apollo-thumb-size", "1px 2px 3px"), ("-apollo-fill-mode", "outside"), ("-apollo-sweep-angle", "180"), ("-apollo-stroke-width", "-1px"), ("-apollo-stroke-dash", "1px 2px 3px 4px 5px"),
          ])
    func invalid(property: String, text: String) {
        #expect(throws: CSSValueError.self) { try parse(property, text) }
    }

    @Test("Schrifteigenschaften erben, Anzeigen nicht; Vorgaben aus der Spec")
    func schemas() {
        for name in ["font-family", "font-size", "font-weight", "font-style", "font-variant-numeric",
                     "line-height", "letter-spacing", "text-align", "-apollo-font-scale", "-apollo-symbol-rendering"] {
            #expect(CSSPropertyRegistry.builtin[name]?.inherits == true, "\(name)")
        }
        for name in ["-apollo-image-rendering", "-apollo-symbol-effect", "-apollo-content-transition",
                     "-apollo-track-color", "-apollo-fill-color", "-apollo-thumb-color", "-apollo-thumb-size",
                     "-apollo-thumb-shadow", "-apollo-fill-mode", "-apollo-sweep-angle", "-apollo-stroke-width", "-apollo-start-angle", "-apollo-fill"] {
            #expect(CSSPropertyRegistry.builtin[name]?.inherits == false, "\(name)")
        }
        #expect(CSSPropertyRegistry.builtin["-apollo-font-scale"]?.initial == .keyword("auto"))
        #expect(CSSPropertyRegistry.builtin["-apollo-image-rendering"]?.initial == .keyword("original"))
        #expect(CSSPropertyRegistry.builtin["-apollo-fill-mode"]?.initial == .keyword("center"))
        #expect(CSSPropertyRegistry.builtin["-apollo-sweep-angle"]?.initial == .angle(360))
        #expect(CSSPropertyRegistry.builtin["-apollo-start-angle"]?.initial == .angle(-90))
    }
}
