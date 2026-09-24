import Testing
import ApolloStyle

@Suite("CSSPropertyRegistry.parse ist von aussen aufrufbar")
struct CSSPropertyRegistryPublicAPITests {
    @Test("liest einen Custom-Property-Wert ohne Hilfsstil")
    func parsesWithoutHelperStyle() throws {
        let value = try CSSPropertyRegistry.parse("width", "44px")
        #expect(value == .length(CSSLength(44, .points)))
    }
}
