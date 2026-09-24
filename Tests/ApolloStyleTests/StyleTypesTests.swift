import ApolloBase
import Testing
@testable import ApolloStyle

@Suite("Stiltypen")
struct StyleTypesTests {
    @Test("die Stufen der Kaskade sind von schwach nach stark geordnet")
    func originOrder() {
        #expect(StyleOrigin.base < .config)
        #expect(StyleOrigin.config < .user)
        #expect(StyleOrigin.user < .inline)
    }

    @Test("jede Pseudoklasse hat ein eigenes Bit und einen CSS-Namen")
    func pseudoStates() {
        let all: [PseudoState] = [.hover, .active, .focus, .checked, .disabled, .open, .firstChild, .lastChild, .invalid]
        #expect(Set(all.map(\.rawValue)).count == 9)
        #expect(all.allSatisfy { $0.rawValue.nonzeroBitCount == 1 })
        #expect(PseudoState.byName["first-child"] == .firstChild)
        #expect(PseudoState.byName["last-child"] == .lastChild)
        #expect(PseudoState.byName.count == 9)
    }

    @Test("ein berechneter Stil liefert Werte über den CSS-Namen")
    func computedStyle() {
        let style = ComputedStyle(values: ["width": .length(CSSLength(12, .points))])
        #expect(style["width"] == .length(CSSLength(value: 12, unit: .points)))
        #expect(style["height"] == nil)
        #expect(style.customProperties.isEmpty)
    }

    @Test("Materialien tragen die CSS-Namen")
    func materialNames() {
        #expect(MaterialThickness(rawValue: "ultra-thin") == .ultraThin)
        #expect(MaterialThickness(rawValue: "ultra-thick") == .ultraThick)
        #expect(MaterialThickness(rawValue: "bar") == .bar)
        #expect(GlassVariant(rawValue: "clear") == .clear)
    }
}
