import Foundation
import Testing
@testable import ApolloStyle

@Suite("CSS: Plakette und :overflowing")
struct BadgePropertiesTests {
    private func parse(_ property: String, _ text: String) throws -> CSSValue {
        try CSSPropertyRegistry.parse(property, text, context: CSSParseContext())
    }

    @Test("-apollo-badge-color liest eine Farbe")
    func color() throws {
        #expect(try parse("-apollo-badge-color", "-apple-system-red") == .color(.system(name: "-apple-system-red", alpha: 1)))
    }

    @Test("-apollo-badge-offset liest x und y, auch negativ")
    func offset() throws {
        #expect(try parse("-apollo-badge-offset", "8px -6px") == .lengths([CSSLength(8, .points), CSSLength(-6, .points)]))
        #expect(throws: CSSValueError.self) { try parse("-apollo-badge-offset", "8px") }
        #expect(throws: CSSValueError.self) { try parse("-apollo-badge-offset", "8% 2px") }
    }

    @Test("-apollo-badge-appear liest Effekte wie -apollo-appear und wird mit der Animationsgeschwindigkeit geteilt")
    func appear() throws {
        let expected = CSSValue.appear([AppearTransition(effects: [.fade, .scale(0.6)], duration: 0.18, curve: .linear)])
        #expect(try parse("-apollo-badge-appear", "fade scale(0.6) 180ms linear") == expected)
        #expect(CSSMotionParser.motionProperties.contains("-apollo-badge-appear"))
    }

    @Test("Plaketten-Eigenschaften erben nicht")
    func notInherited() {
        for name in ["-apollo-badge-color", "-apollo-badge-offset", "-apollo-badge-appear"] {
            #expect(CSSPropertyRegistry.builtin[name]?.inherits == false)
        }
    }

    @Test(":overflowing ist eine Pseudoklasse")
    func overflowing() {
        #expect(PseudoState.byName["overflowing"] == .overflowing)
    }
}
