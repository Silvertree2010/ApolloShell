import Testing
@testable import ApolloStyle

private let ease = TimingCurve.cubicBezier(0.25, 0.1, 0.25, 1)
private let easeOut = TimingCurve.cubicBezier(0, 0, 0.58, 1)
private let spatial = TimingCurve.cubicBezier(0.38, 1.21, 0.22, 1)
private let emphasized = TimingCurve.cubicBezier(0.2, 0, 0, 1)

@Suite("CSS: Bewegung")
struct CSSMotionPropertiesTests {
    private func parse(_ property: String, _ text: String) throws -> CSSValue {
        try CSSPropertyRegistry.parse(property, text, context: CSSParseContext())
    }

    @Test("benannte Kurven aus CSS und 0.1.4.2",
          arguments: [
              ("linear", TimingCurve.linear),
              ("ease", ease),
              ("ease-in", .cubicBezier(0.42, 0, 1, 1)),
              ("ease-out", easeOut),
              ("ease-in-out", .cubicBezier(0.42, 0, 0.58, 1)),
              ("spatial", spatial),
              ("effects", .cubicBezier(0.34, 0.8, 0.34, 1)),
              ("effects-slow", .cubicBezier(0.34, 0.88, 0.34, 1)),
              ("emphasized", emphasized),
              ("cubic-bezier(0.1, 0.2, 0.3, 1.4)", .cubicBezier(0.1, 0.2, 0.3, 1.4)),
              ("spring(0.4, 0.8)", .spring(response: 0.4, damping: 0.8)),
          ])
    func curves(text: String, expected: TimingCurve) throws {
        #expect(try parse("transition", "all 100ms \(text)") == .transitions([Transition(property: "all", duration: 0.1, curve: expected)]))
    }

    @Test("Übergänge aus der Default-Config")
    func transitions() throws {
        #expect(try parse("transition", "all 500ms spatial") == .transitions([Transition(property: "all", duration: 0.5, curve: spatial)]))
        #expect(try parse("transition", "background 120ms ease-out") == .transitions([Transition(property: "background", duration: 0.12, curve: easeOut)]))
        #expect(try parse("transition", "value 600ms emphasized, size 500ms spatial") == .transitions([
            Transition(property: "value", duration: 0.6, curve: emphasized),
            Transition(property: "size", duration: 0.5, curve: spatial),
        ]))
        #expect(try parse("transition", "content 200ms") == .transitions([Transition(property: "content", duration: 0.2, curve: ease)]))
        #expect(try parse("transition", "match 300ms spring(0.4, 0.8)") == .transitions([
            Transition(property: "match", duration: 0.3, curve: .spring(response: 0.4, damping: 0.8)),
        ]))
        #expect(try parse("transition", "transform 1s linear") == .transitions([Transition(property: "transform", duration: 1, curve: .linear)]))
        #expect(try parse("transition", "none") == .transitions([]))
    }

    @Test("ungültige Übergänge",
          arguments: ["foo 1s", "all", "all 1s ease ease", "all -1s", "animation 1s", "transition 1s",
                      "all 1s cubic-bezier(2, 0, 0, 1)", "all 1s spring(0, 1)", "all 1s bouncy"])
    func invalidTransitions(text: String) {
        #expect(throws: CSSValueError.self) { try parse("transition", text) }
    }

    @Test("Erscheinen und Verschwinden")
    func appear() throws {
        #expect(try parse("-apollo-appear", "fade scale(0.6) 180ms ease-out") == .appear([
            AppearTransition(effects: [.fade, .scale(0.6)], duration: 0.18, curve: easeOut),
        ]))
        #expect(try parse("-apollo-disappear", "slide(bottom 12px) blur(8px) 200ms, fade 100ms") == .appear([
            AppearTransition(effects: [.slide(edge: "bottom", distance: 12), .blur(8)], duration: 0.2, curve: ease),
            AppearTransition(effects: [.fade], duration: 0.1, curve: ease),
        ]))
        #expect(try parse("-apollo-appear", "slide(left) 1s") == .appear([
            AppearTransition(effects: [.slide(edge: "leading", distance: nil)], duration: 1, curve: ease),
        ]))
        #expect(try parse("-apollo-appear", "none") == .appear([]))
        #expect(throws: CSSValueError.self) { try parse("-apollo-appear", "200ms") }
        #expect(throws: CSSValueError.self) { try parse("-apollo-appear", "fade") }
        #expect(throws: CSSValueError.self) { try parse("-apollo-appear", "spin 1s") }
        #expect(throws: CSSValueError.self) { try parse("-apollo-appear", "slide(middle) 1s") }
        #expect(throws: CSSValueError.self) { try parse("-apollo-appear", "200ms fade") }
    }

    @Test("Transform")
    func transform() throws {
        #expect(try parse("transform", "rotate(-90deg)") == .transform([.rotate(-90)]))
        #expect(try parse("transform", "scale(1.1) translate(4px, -2px) rotate(0)") == .transform([.scale(1.1), .translate(4, -2), .rotate(0)]))
        #expect(try parse("transform", "translate(3px)") == .transform([.translate(3, 0)]))
        #expect(try parse("transform", "none") == .transform([]))
        #expect(throws: CSSValueError.self) { try parse("transform", "skew(10deg)") }
        #expect(throws: CSSValueError.self) { try parse("transform", "rotate(90)") }
        #expect(throws: CSSValueError.self) { try parse("transform", "scale(1, 2)") }
    }

    @Test("Animation und Verzögerung")
    func animation() throws {
        #expect(try parse("animation", "bounce 440ms infinite") == .animation(name: "bounce", duration: 0.44, repeatCount: nil))
        #expect(try parse("animation", "spin 1s") == .animation(name: "spin", duration: 1, repeatCount: 1))
        #expect(try parse("animation", "wiggle 250ms 3") == .animation(name: "wiggle", duration: 0.25, repeatCount: 3))
        #expect(try parse("animation", "pulse 2s infinite") == .animation(name: "pulse", duration: 2, repeatCount: nil))
        #expect(try parse("animation", "none") == .keyword("none"))
        #expect(throws: CSSValueError.self) { try parse("animation", "shake 1s") }
        #expect(throws: CSSValueError.self) { try parse("animation", "spin 0s") }
        #expect(throws: CSSValueError.self) { try parse("animation", "spin 1s 0") }
        #expect(throws: CSSValueError.self) { try parse("animation", "spin") }
        #expect(try parse("animation-delay", "-0.07s") == .duration(-0.07))
        #expect(try parse("animation-delay", "calc(3 * -70ms)") == .duration(3 * -0.07))
        #expect(throws: CSSValueError.self) { try parse("animation-delay", "1px") }
    }

    @Test("die Registry enthält genau die Eigenschaften aus styling.md 3")
    func completeRegistry() {
        let expected: Set<String> = [
            "width", "height", "min-width", "max-width", "min-height", "max-height", "aspect-ratio", "padding", "margin",
            "gap", "row-gap", "column-gap", "flex-grow", "flex-shrink", "align-items", "align-self", "justify-content",
            "grid-template-columns", "grid-auto-rows", "grid-column", "grid-row", "overflow", "z-index", "pointer-events", "cursor",
            "color", "accent-color", "background", "background-color", "opacity", "border", "border-width", "border-color",
            "border-radius", "-apollo-corner-shape", "box-shadow", "filter", "-apollo-fade-edges", "-apollo-join-radius",
            "-apollo-badge-color", "-apollo-badge-offset", "-apollo-badge-appear",
            "font-family", "font-size", "font-weight", "font-style", "font-variant-numeric", "line-height", "letter-spacing",
            "text-align", "-apollo-font-scale", "-apollo-image-rendering", "-apollo-symbol-rendering", "-apollo-symbol-effect",
            "-apollo-content-transition",
            "-apollo-track-color", "-apollo-fill-color", "-apollo-thumb-color", "-apollo-thumb-size", "-apollo-thumb-shadow",
            "-apollo-sweep-angle", "-apollo-stroke-width", "-apollo-start-angle", "-apollo-fill",
            "transition", "-apollo-appear", "-apollo-disappear", "transform", "animation-delay", "animation",
        ]
        #expect(expected.count == 70)
        #expect(Set(CSSPropertyRegistry.builtin.keys) == expected)
        #expect(CSSPropertyRegistry.groups.map(\.count).reduce(0, +) == 70)
        #expect(CSSPropertyRegistry.builtin.values.allSatisfy { $0.feature == "core" })
    }
}
