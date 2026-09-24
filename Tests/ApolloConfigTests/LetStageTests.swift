import Testing
import Foundation
import ApolloBase
@testable import ApolloConfig

@Suite("LetStage")
struct LetStageTests {
    static func expand(_ files: [String: String], entry: String = "/config/shell.kdl") -> [ExpandedNode] {
        let fs = MemoryFileSystem(files)
        let paths = ConfigPaths(
            builtinConfigs: URL(fileURLWithPath: "/builtin"),
            userConfig: URL(fileURLWithPath: "/config"),
            applicationSupport: URL(fileURLWithPath: "/support")
        )
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: paths)
        #expect(result.diagnostics.isEmpty)
        return result.nodes
    }

    static func run(_ text: String) -> LetStageResult {
        LetStage.run(Self.expand(["/config/shell.kdl": text]), registry: .builtin)
    }

    @Test("Eine Form-A Konstante wird ausgewertet")
    func formAConstantEvaluates() {
        let result = Self.run("let gap=8 radius=12")
        #expect(result.diagnostics.isEmpty)
        #expect(result.values["gap"] == .number(8))
        #expect(result.values["radius"] == .number(12))
        #expect(result.nodes.isEmpty)
    }

    @Test("Eine Form-A Konstante kann eine fruehere referenzieren")
    func formAConstantReferencesEarlierOne() {
        let result = Self.run("let gap=8\nlet columns=\"{gap * 2}\"")
        #expect(result.diagnostics.isEmpty)
        #expect(result.values["columns"] == .number(16))
    }

    @Test("Form B mit Record-Kindern wird ausgewertet")
    func formBWithRecordChildrenEvaluates() {
        let result = Self.run("let sidebar-minimal {\n  - kind=\"spaces\" style=\"dots\"\n  - kind=\"spacer\"\n}")
        #expect(result.diagnostics.isEmpty)
        let expected = Value.list([
            .record(Record([("kind", .string("spaces")), ("style", .string("dots"))])),
            .record(Record([("kind", .string("spacer"))])),
        ])
        #expect(result.values["sidebar-minimal"] == expected)
    }

    @Test("let auf oberster Ebene gilt bis zum Ende der Datei")
    func topLevelLetIsVisibleForRestOfFile() {
        let result = Self.run("let a=1\ndock {}\nlet b=\"{a + 1}\"")
        #expect(result.diagnostics.isEmpty)
        #expect(result.values["b"] == .number(2))
    }

    @Test("let ist vor seiner Deklaration nicht sichtbar")
    func letIsNotVisibleBeforeItsDeclaration() {
        let result = Self.run("let b=\"{a + 1}\"\nlet a=1")
        #expect(result.diagnostics.contains { $0.severity == .error && $0.message.contains("'a'") })
        #expect(result.values["b"] == nil)
    }

    @Test("let ist im inneren Block sichtbar")
    func letIsVisibleInsideAnInnerBlock() {
        let result = Self.run("let a=1\ndock {\n  let b=\"{a + 1}\"\n}")
        #expect(result.diagnostics.isEmpty)
        #expect(result.values["b"] == .number(2))
    }

    @Test("let aus einem inneren Block ist ausserhalb nicht sichtbar")
    func letFromInnerBlockIsNotVisibleOutside() {
        let result = Self.run("dock {\n  let a=1\n}\nlet b=\"{a + 1}\"")
        #expect(result.diagnostics.contains { $0.severity == .error && $0.message.contains("'a'") })
    }

    @Test("let ist ueber include hinweg sichtbar")
    func letIsVisibleAcrossInclude() {
        let result = LetStage.run(Self.expand([
            "/config/shell.kdl": "let a=1\ninclude \"more.kdl\"",
            "/config/more.kdl": "let b=\"{a + 1}\"",
        ]), registry: .builtin)
        #expect(result.diagnostics.isEmpty)
        #expect(result.values["b"] == .number(2))
    }

    @Test("let in der eingebundenen Datei ist danach in der einbindenden Datei sichtbar")
    func letFromIncludedFileIsVisibleAfterwards() {
        let result = LetStage.run(Self.expand([
            "/config/shell.kdl": "include \"colors.kdl\"\nlet double=\"{accent-weight * 2}\"",
            "/config/colors.kdl": "let accent-weight=3",
        ]), registry: .builtin)
        #expect(result.diagnostics.isEmpty)
        #expect(result.values["double"] == .number(6))
    }

    @Test("Zweites let mit gleichem Namen im selben Bereich ist ein Fehler")
    func duplicateLetInSameScopeFails() {
        let result = Self.run("let a=1\nlet a=2")
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .error)
        #expect(result.diagnostics[0].message.contains("duplicate"))
    }

    @Test("let im inneren Bereich verdeckt das aeussere mit Warnung")
    func letInInnerScopeShadowsOuterWithWarning() {
        let result = Self.run("let a=1\ndock {\n  let a=2\n}")
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .warning)
        #expect(result.diagnostics[0].message.contains("shadows"))
    }

    @Test("let mit dem Namen einer festen Wurzel ist ein Fehler")
    func letNamedAfterFixedRootFails() {
        let result = Self.run("let var=1")
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .error)
        #expect(result.diagnostics[0].message.contains("'var'"))
    }

    @Test("let mit dem Namen eines Providers von 0.2.0 ist ein Fehler")
    func letNamedAfterExistingProviderFails() {
        let result = Self.run("let perf=1")
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .error)
        #expect(result.diagnostics[0].message.contains("'perf'"))
    }

    @Test("let mit dem Namen eines zukuenftigen Providers ist eine Notiz")
    func letNamedAfterFutureProviderIsANote() {
        let result = Self.run("let wallpaper=1")
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .note)
        #expect(result.diagnostics[0].message.contains("wallpaper"))
        #expect(result.values["wallpaper"] == .number(1))
    }

    @Test("let darf nicht auf einen Provider verweisen")
    func letCannotReferenceAProvider() {
        let result = Self.run("let cpu=\"{perf.cpu}\"")
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .error)
        #expect(result.diagnostics[0].message.contains("'perf'"))
    }

    @Test("let darf nicht auf var verweisen")
    func letCannotReferenceVar() {
        let result = Self.run("let x=\"{var.launcher-query}\"")
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .error)
        #expect(result.diagnostics[0].message.contains("'var'"))
    }

    @Test("Versteckter Laufzeitbezug in einem Record-Feld ist ein Fehler")
    func hiddenRuntimeReferenceInRecordFieldFails() {
        let result = Self.run("let preset {\n  - kind=\"clock\" value=\"{clock.now}\"\n}")
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .error)
        #expect(result.diagnostics[0].message.contains("'clock'"))
    }

    @Test("let mit fester POSIX-Auswertung formatiert Zahlen ohne Tausendertrennzeichen")
    func letUsesFixedPOSIXContext() {
        let result = Self.run("let big=\"{1234 | grouped}\"")
        #expect(result.diagnostics.isEmpty)
        #expect(result.values["big"] == .string("1,234"))
    }

    @Test("let mit 50000 Listeneintraegen laedt im Zeitbudget")
    func largeFormBListLoadsWithinBudget() {
        var text = "let big {\n"
        for index in 0..<50_000 {
            text += "  - \(index)\n"
        }
        text += "}\n"
        let start = Date()
        let result = Self.run(text)
        let elapsed = Date().timeIntervalSince(start)
        #expect(result.diagnostics.isEmpty)
        if case .list(let items)? = result.values["big"] {
            #expect(items.count == 50_000)
        } else {
            Issue.record("expected a list")
        }
        #expect(elapsed < 5)
    }

    @Test("Form B mit Skalar-Argument ist ein Fehler")
    func formBWithScalarArgumentFails() {
        let result = Self.run("let a 5")
        #expect(result.diagnostics.contains { $0.severity == .error })
    }

    @Test("let ohne Konstanten ist ein Fehler")
    func letWithoutConstantsFails() {
        let result = Self.run("let")
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .error)
    }

    @Test("Knoten tragen die sichtbaren let-Werte ihres Bereichs")
    func nodesCarryVisibleLetValues() {
        let result = Self.run("let a=1\ndock {\n  let b=2\n  text {}\n}")
        #expect(result.diagnostics.isEmpty)
        let dock = result.nodes.first { $0.kdl.name == "dock" }
        #expect(dock?.letValues["a"] == .number(1))
        #expect(dock?.letValues["b"] == nil)
        let text = dock?.children.first { $0.kdl.name == "text" }
        #expect(text?.letValues["a"] == .number(1))
        #expect(text?.letValues["b"] == .number(2))
    }

    @Test("Knoten sehen ein spaeter im selben Bereich deklariertes let")
    func nodesSeeALaterLetInTheSameScope() {
        let result = Self.run("dock {}\nlet a=1")
        #expect(result.diagnostics.isEmpty)
        let dock = result.nodes.first { $0.kdl.name == "dock" }
        #expect(dock?.letValues["a"] == .number(1))
    }

    @Test("Fehler eines let in einer eingebundenen Datei tragen die include-Kette")
    func letErrorInIncludedFileCarriesIncludeChain() {
        let result = LetStage.run(Self.expand([
            "/config/shell.kdl": "include \"more.kdl\"",
            "/config/more.kdl": "let var=1",
        ]), registry: .builtin)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].notes.contains { $0.message.contains("included from") })
    }
}
