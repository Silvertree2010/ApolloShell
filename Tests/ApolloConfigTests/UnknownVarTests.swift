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

    @Test("Ein vertippter Aufzählungswert bekommt einen Vorschlag")
    func enumerationSuggestion() {
        let result = LoaderHarness.load(["/config/shell.kdl": "panel \"p\" anchor=\"lft\" {\n    text \"x\"\n}"])
        let error = result.diagnostics.first { $0.severity == .error }
        #expect(error?.message.hasPrefix("property 'anchor' expects") == true)
        #expect(error?.help == "did you mean 'left'?")
    }

    @Test("set, toggle-var und reset auf eine nicht deklarierte var warnen beim Laden")
    func unknownVarInActions() {
        let result = LoaderHarness.load(["/config/shell.kdl": """
        var open #false
        panel "p" anchor="left" {
            button {
                on-click {
                    set "opne" #true
                    toggle-var "open"
                    reset "closed"
                }
            }
        }
        """])
        #expect(result.ir != nil)
        let warnings = result.diagnostics.filter { $0.severity == .warning }
        #expect(warnings.map(\.message) == ["unknown var 'opne'", "unknown var 'closed'"])
        #expect(warnings.first?.help == "did you mean 'open'?")
    }
}
