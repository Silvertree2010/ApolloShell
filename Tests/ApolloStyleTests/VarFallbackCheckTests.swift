import Testing
import ApolloBase
import ApolloStyle

@Suite("check prüft var()-Fallbacks")
struct VarFallbackCheckTests {
    @Test("ungültiger Fallback wird gemeldet, gültige, fallbacklose und Custom-Property-Deklarationen nicht")
    func fallbacks() {
        let css = """
        #a { background: var(--apollo-panel-fill, material(sidebar)); }
        #b { background: var(--apollo-panel-fill, glass(regular)); color: var(--tx); --x: var(--y, nonsense()); }
        #c { padding: var(--p, 4px 8px); opacity: var(--o, inherit); }
        """
        let (sheet, parsed) = StyleSheet.parse(css, file: "s.css", origin: .config)
        #expect(parsed.isEmpty)
        let found = sheet.fallbackProblems()
        #expect(found.count == 1, "\(found.map(\.message))")
        #expect(found.first?.span?.start.line == 1)
        #expect(found.first?.message.contains("background") == true)
    }
}
