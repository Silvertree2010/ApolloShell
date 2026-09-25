import Testing
import ApolloStyle
@testable import ApolloShell

@MainActor
@Suite("Zähler neu berechneter Stile für apollo stats (V7)")
struct StyleCountTests {
    @Test("nur Cache-Fehlgriffe zählen, über alle Resolver hinweg")
    func countsMissesAcrossResolvers() throws {
        let (session, _) = try RenderProbe.session("panel \"t\" anchor=\"left\" { stack class=\"x\" }", css: ".x { width: 3px; }")
        let styles = session.context.styles
        let subject = StyleSubject(kind: "stack", classes: ["style-count-probe"])
        let before = StyleResolver.computedTotal
        _ = styles.resolve(subject, ancestors: [], parent: nil)
        _ = styles.resolve(subject, ancestors: [], parent: nil)
        #expect(StyleResolver.computedTotal - before == 1)
    }
}
