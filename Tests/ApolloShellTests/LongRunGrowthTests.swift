import Testing
import ApolloBase
import ApolloStyle
@testable import ApolloShell

@MainActor
@Suite("Dauerbetrieb: Listen wachsen nicht ohne Ende")
struct LongRunGrowthTests {
    @Test("ungültiger Wert im Stylesheet: jeder neu berechnete Stil hängt keine weitere Meldung an")
    func styleDiagnosticsStayBounded() throws {
        let (session, _) = try RenderProbe.session("panel \"t\" anchor=\"left\" { stack class=\"x\" }", css: ".x { color: var(--missing); }")
        let styles = session.context.styles
        let start = styles.diagnostics.count
        for step in 0..<500 {
            _ = styles.resolve(StyleSubject(kind: "stack", classes: ["x"]), ancestors: [], parent: nil, inline: "opacity: 0.\(step)")
        }
        #expect(styles.diagnostics.count - start <= 1)
    }

    @Test("ungültiger Wert mit wechselndem Text im Inline-Stil: Meldungen bleiben gedeckelt")
    func changingInlineDiagnosticsStayCapped() throws {
        let (session, _) = try RenderProbe.session("panel \"t\" anchor=\"left\" { stack class=\"x\" }")
        let styles = session.context.styles
        for step in 0..<2000 {
            _ = styles.resolve(StyleSubject(kind: "stack"), ancestors: [], parent: nil, inline: "background: linear-gradient(red q\(step), blue)")
        }
        #expect(styles.diagnostics.count <= StyleResolver.diagnosticLimit)
    }

    @Test("dieselbe Warnung tausendfach: die Warnungsliste der Assembly wächst nicht mit")
    func repeatedWarningsStayBounded() throws {
        let (session, _) = try RenderProbe.session("panel \"t\" anchor=\"left\" { stack {} }")
        let assembly = session.assembly
        let start = assembly.warnings.count
        for _ in 0..<1000 {
            assembly.vars.set("nirgends", .number(1))
        }
        #expect(assembly.warnings.count - start <= 1)
    }
}
