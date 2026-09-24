import Testing
import Foundation
import ApolloBase
import ApolloKDL
@testable import ApolloConfig

@Suite("DisableStage nach use")
struct DisableStageTests {
    static func pipeline(_ text: String) -> (nodes: [ExpandedNode], featureDiagnostics: [Diagnostic], useDiagnostics: [Diagnostic], disableDiagnostics: [Diagnostic]) {
        let fs = MemoryFileSystem(["/config/shell.kdl": text])
        let included = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: UseStageTests.paths)
        #expect(included.diagnostics.isEmpty)
        let featured = FeatureStage.run(included.nodes, shellVersion: "0.2.0", registry: .builtin)
        let lets = LetStage.run(featured.nodes, registry: .builtin)
        let used = UseStage.run(lets.nodes, registry: .builtin)
        let disabled = DisableStage.run(used.nodes, registry: .builtin)
        return (disabled.nodes, featured.diagnostics, used.diagnostics, disabled.diagnostics)
    }

    @Test("disable bind wirkt auf ein bind, das ein use erzeugt")
    func disableBindCreatedByUse() {
        let result = Self.pipeline("""
        define "launcher-key" {
            bind "alt+space" {
                toggle "launcher"
            }
        }
        use "launcher-key"
        disable bind="alt+space"
        dock {}
        """)
        #expect(result.featureDiagnostics.isEmpty)
        #expect(result.useDiagnostics.isEmpty)
        #expect(result.disableDiagnostics.isEmpty)
        #expect(result.nodes.map(\.kdl.name) == ["dock"])
    }

    @Test("override einer Oberflaeche wirkt auf eine per use erzeugte Oberflaeche")
    func overrideSurfaceCreatedByUse() {
        let result = Self.pipeline("""
        define "clock-panel" {
            panel "desktop-clock" {
                text "old"
            }
        }
        use "clock-panel"
        panel "desktop-clock" override=#true {
            text "new"
        }
        """)
        #expect(result.featureDiagnostics.isEmpty)
        #expect(result.useDiagnostics.isEmpty)
        #expect(result.disableDiagnostics.isEmpty)
        #expect(result.nodes.map(\.kdl.name) == ["panel"])
        #expect(result.nodes.first?.children.first.map { UseStageTests.firstArgument($0) } == "new")
    }

    @Test("Doppelte Oberflaeche aus use ohne override ist ein Fehler")
    func duplicateSurfaceFromUseFails() {
        let result = Self.pipeline("""
        define "clock-panel" {
            panel "desktop-clock" {}
        }
        use "clock-panel"
        panel "desktop-clock" {}
        """)
        #expect(result.disableDiagnostics.map(\.severity) == [.error])
    }
}
