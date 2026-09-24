import Testing
import Foundation
import ApolloBase
import ApolloKDL
@testable import ApolloConfig

@Suite("FeatureStage")
struct FeatureStageTests {
    func expand(_ text: String) -> [ExpandedNode] {
        let fs = MemoryFileSystem(["/config/shell.kdl": text])
        let paths = ConfigPaths(
            builtinConfigs: URL(fileURLWithPath: "/builtin"),
            userConfig: URL(fileURLWithPath: "/config"),
            applicationSupport: URL(fileURLWithPath: "/support")
        )
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: paths)
        #expect(result.diagnostics.isEmpty)
        return result.nodes
    }

    func names(_ nodes: [ExpandedNode]) -> [String] {
        nodes.map(\.kdl.name)
    }

    @Test("require mit erfuellter Version laedt ohne Fehler")
    func requireVersionSatisfied() {
        let nodes = expand("require \"0.2.0\"\ndock {}")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.diagnostics.isEmpty)
        #expect(names(result.nodes) == ["dock"])
    }

    @Test("require mit zu hoher Version bricht das Laden ab")
    func requireVersionTooHigh() {
        let nodes = expand("require \"0.3.0\"\ndock {}")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.nodes.isEmpty)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .error)
        #expect(result.diagnostics[0].message.contains("0.3.0"))
    }

    @Test("Versionsvergleich ist zahlenweise, nicht lexikographisch", arguments: [
        ("0.2.0", "0.2.0", true),
        ("0.2.10", "0.2.9", true),
        ("0.2.9", "0.2.10", false),
        ("0.10.0", "0.2.10", true),
        ("0.2.10", "0.10.0", false),
    ])
    func versionComparisonIsNumeric(shellVersion: String, required: String, shouldLoad: Bool) {
        let nodes = expand("require \"\(required)\"")
        let result = FeatureStage.run(nodes, shellVersion: shellVersion, registry: .builtin)
        #expect(result.diagnostics.isEmpty == shouldLoad)
    }

    @Test("Ungueltige Version ist ein Fehler")
    func invalidVersionFails() {
        let nodes = expand("require \"not-a-version\"")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].message.contains("invalid version"))
    }

    @Test("require feature bekannt und vorhanden laedt")
    func requireKnownFeaturePresent() {
        let nodes = expand("require feature=\"wm\"\ndock {}")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.diagnostics.isEmpty)
        #expect(names(result.nodes) == ["dock"])
    }

    @Test("require feature unbekannt bricht ab")
    func requireUnknownFeatureFails() {
        let nodes = expand("require feature=\"time-travel\"")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .error)
    }

    @Test("Unbekanntes Feature wird uebersprungen und meldet eine Notiz, Inhalt wird nicht geprueft")
    func unknownFeatureSkipsWithNote() {
        let nodes = expand("feature \"menu-mirror\" {\n  totally-made-up-node oops=1\n}")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.nodes.isEmpty)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .note)
        #expect(result.diagnostics[0].message.contains("menu-mirror"))
    }

    @Test("Bekanntes Feature wird gebaut")
    func knownFeatureIsBuilt() {
        let nodes = expand("feature \"wm\" {\n  dock {}\n}")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.diagnostics.isEmpty)
        #expect(names(result.nodes) == ["dock"])
    }

    @Test("else greift, wenn das Feature fehlt")
    func elsePairsWithMissingFeature() {
        let nodes = expand("feature \"time-travel\" {\n  a {}\n}\nelse {\n  b {}\n}")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(names(result.nodes) == ["b"])
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .note)
    }

    @Test("else wird uebersprungen, wenn das Feature vorhanden ist")
    func elseSkippedWhenFeaturePresent() {
        let nodes = expand("feature \"wm\" {\n  a {}\n}\nelse {\n  b {}\n}")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(names(result.nodes) == ["a"])
        #expect(result.diagnostics.isEmpty)
    }

    @Test("else ohne Vorgaenger ist ein Fehler")
    func elseWithoutPredecessorFails() {
        let nodes = expand("else {\n  a {}\n}")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .error)
        #expect(result.diagnostics[0].message.contains("else"))
    }

    @Test("when else bleibt fuer eine spaetere Stufe unangetastet")
    func whenElsePassesThroughUnchanged() {
        let nodes = expand("when \"{battery.present}\" {\n  a {}\n}\nelse {\n  b {}\n}")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.diagnostics.isEmpty)
        #expect(names(result.nodes) == ["when", "else"])
        #expect(names(result.nodes[0].children) == ["a"])
        #expect(names(result.nodes[1].children) == ["b"])
    }

    @Test("feature else bleibt weiterhin korrekt neben when else")
    func featureElseStillWorksAlongsideWhenElse() {
        let nodes = expand(
            "when \"{battery.present}\" {\n  a {}\n}\nelse {\n  b {}\n}\n" +
            "feature \"time-travel\" {\n  c {}\n}\nelse {\n  d {}\n}"
        )
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .note)
        #expect(names(result.nodes) == ["when", "else", "d"])
    }

    @Test("verwaistes else ohne when oder feature bleibt ein Fehler")
    func orphanElseStillFailsAmongWhenElse() {
        let nodes = expand("when \"{battery.present}\" {\n  a {}\n}\nelse {\n  b {}\n}\nelse {\n  c {}\n}")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .error)
        #expect(result.diagnostics[0].message.contains("else"))
        #expect(names(result.nodes) == ["when", "else"])
    }

    @Test("verschachteltes when else bleibt in Kindknoten unangetastet")
    func nestedWhenElsePassesThroughUnchanged() {
        let nodes = expand("dock {\n  when \"{battery.present}\" {\n    a {}\n  }\n  else {\n    b {}\n  }\n}")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.diagnostics.isEmpty)
        #expect(names(result.nodes) == ["dock"])
        #expect(names(result.nodes[0].children) == ["when", "else"])
    }

    @Test("feature in Handler-Aktionen wird aufgeloest")
    func featureInHandlerActions() {
        let nodes = expand("bind \"alt+space\" {\n  feature \"wm\" {\n    wm.focus \"left\"\n  }\n}")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.diagnostics.isEmpty)
        #expect(names(result.nodes) == ["bind"])
        #expect(names(result.nodes[0].children) == ["wm.focus"])
    }

    @Test("disable surface entfernt die Oberflaeche, Position spielt keine Rolle")
    func disableSurfaceBeforeAndAfterTarget() {
        let before = expand("disable surface=\"desktop-clock\"\npanel \"desktop-clock\" {}\ndock {}")
        let after = expand("panel \"desktop-clock\" {}\ndisable surface=\"desktop-clock\"\ndock {}")
        for nodes in [before, after] {
            let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
            #expect(result.diagnostics.isEmpty)
            #expect(names(result.nodes) == ["dock"])
        }
    }

    @Test("disable bind vergleicht normalisierte Tastenkombinationen")
    func disableBindComparesNormalizedChords() {
        let nodes = expand("bind \"option+space\" {\n  a {}\n}\ndisable bind=\"alt+space\"")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.diagnostics.isEmpty)
        #expect(result.nodes.isEmpty)
    }

    @Test("disable on entfernt einen Ereignis-Handler")
    func disableOnRemovesEventHandler() {
        let nodes = expand("on \"battery.warning\" {\n  a {}\n}\ndisable on=\"battery.warning\"")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.diagnostics.isEmpty)
        #expect(result.nodes.isEmpty)
    }

    @Test("disable auf ein unbekanntes Ziel ist eine Warnung")
    func disableUnknownTargetWarns() {
        let nodes = expand("disable surface=\"does-not-exist\"")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .warning)
    }

    @Test("disable wirkt auf die per override ersetzte Oberflaeche")
    func disableActsOnOverriddenSurface() {
        let nodes = expand(
            "panel \"desktop-clock\" {\n  text \"first\"\n}\n" +
            "panel \"desktop-clock\" override=#true {\n  text \"second\"\n}\n" +
            "disable surface=\"desktop-clock\"\n" +
            "dock {}"
        )
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.diagnostics.isEmpty)
        #expect(names(result.nodes) == ["dock"])
    }

    @Test("override haelt Position des ersten, Inhalt des letzten")
    func overrideKeepsFirstPositionAndLastContent() {
        let nodes = expand(
            "define \"a\" {\n  text \"first\"\n}\n" +
            "dock {}\n" +
            "define \"a\" override=#true {\n  text \"second\"\n}"
        )
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.diagnostics.isEmpty)
        #expect(names(result.nodes) == ["define", "dock"])
        #expect(names(result.nodes[0].children) == ["text"])
        let textArgument = result.nodes[0].children[0].kdl.arguments.first
        var textValue: String?
        if case .string(let value) = textArgument?.scalar {
            textValue = value
        }
        #expect(textValue == "second")
    }

    @Test("Zweites define ohne override ist ein Fehler mit beiden Orten")
    func duplicateDefineWithoutOverrideFails() {
        let nodes = expand("define \"a\" {\n  text \"first\"\n}\ndefine \"a\" {\n  text \"second\"\n}")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .error)
        #expect(!result.diagnostics[0].notes.isEmpty)
    }

    @Test("override ohne Vorgaenger ist eine Warnung")
    func overrideWithoutPredecessorWarns() {
        let nodes = expand("define \"a\" override=#true {\n  text \"first\"\n}")
        let result = FeatureStage.run(nodes, shellVersion: "0.2.0", registry: .builtin)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .warning)
    }

    @Test("Zwei bind mit gleichbedeutender Tastenschreibweise brauchen override")
    func twoEquivalentBindsNeedOverride() {
        let failing = expand("bind \"alt+space\" {\n  a {}\n}\nbind \"option+space\" {\n  b {}\n}")
        let failingResult = FeatureStage.run(failing, shellVersion: "0.2.0", registry: .builtin)
        #expect(failingResult.diagnostics.contains { $0.severity == .error })

        let overridden = expand("bind \"alt+space\" {\n  a {}\n}\nbind \"option+space\" override=#true {\n  b {}\n}")
        let overriddenResult = FeatureStage.run(overridden, shellVersion: "0.2.0", registry: .builtin)
        #expect(overriddenResult.diagnostics.isEmpty)
        #expect(overriddenResult.nodes.count == 1)
        #expect(names(overriddenResult.nodes[0].children) == ["b"])
    }
}
