import Testing
import ApolloBase
@testable import ApolloConfig

@Suite("Unbekannte var beim Laden")
struct UnknownVarTests {
    @Test("Lesen einer nicht deklarierten var warnt mit Vorschlag, deklarierte und ganze var bleiben still")
    func unknownVarWarns() throws {
        let result = LoaderHarness.load(["/config/shell.kdl": """
        var launcher-query ""
        panel "p" anchor="left" {
            text "{var.launcher-qury}"
            text "{var.launcher-query}"
        }
        """])
        #expect(result.ir != nil)
        let warnings = result.diagnostics.filter { $0.severity == .warning }
        #expect(warnings.map(\.message) == ["unknown var 'launcher-qury'"])
        #expect(warnings.first?.help == "did you mean 'launcher-query'?")
        #expect(warnings.first?.span?.start.line == 3)
    }
}
