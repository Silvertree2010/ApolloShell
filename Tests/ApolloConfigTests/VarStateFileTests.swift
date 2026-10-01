import Testing
import Foundation
import ApolloBase
@testable import ApolloConfig

@Suite("VarStateFile read")
struct VarStateFileReadTests {
    static func decl(_ name: String, _ type: ValueType, persist: Bool = true, derived: Bool = false) -> VarDecl {
        VarDecl(
            name: name,
            type: type,
            defaultValue: .scalar(CompiledValue(template: .literal(""), dependencies: [], span: .synthetic())),
            persist: persist,
            derived: derived ? CompiledValue(template: .literal(""), dependencies: [], span: .synthetic()) : nil,
            span: .synthetic()
        )
    }

    @Test("Bekannter Wert wird gelesen")
    func knownValueIsRead() {
        let (values, diagnostics) = VarStateFile.read("dashboard-tab \"media\"\n", file: "state.kdl", declarations: [Self.decl("dashboard-tab", .string)])
        #expect(diagnostics.isEmpty)
        #expect(values["dashboard-tab"] == .string("media"))
    }

    @Test("Unbekannter Knoten wird ignoriert")
    func unknownNodeIsIgnored() {
        let (values, diagnostics) = VarStateFile.read("mystery 1\n", file: "state.kdl", declarations: [])
        #expect(diagnostics.isEmpty)
        #expect(values.isEmpty)
    }

    @Test("Nicht parsbare Datei ergibt Vorgaben und Warnung")
    func unparsableFileGivesDefaultsAndWarning() {
        let (values, diagnostics) = VarStateFile.read("dashboard-tab \"unterminated", file: "state.kdl", declarations: [Self.decl("dashboard-tab", .string)])
        #expect(values.isEmpty)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .warning)
        #expect(diagnostics[0].message.contains("could not be parsed"))
    }

    @Test("Falscher Typ wird verworfen mit Warnung")
    func wrongTypeIsDiscardedWithWarning() {
        let (values, diagnostics) = VarStateFile.read("dashboard-tab 5\n", file: "state.kdl", declarations: [Self.decl("dashboard-tab", .string)])
        #expect(values["dashboard-tab"] == nil)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .warning)
    }

    @Test("Liste statt Record wird abgelehnt")
    func listInsteadOfRecordIsRejected() {
        let (values, diagnostics) = VarStateFile.read("weather-place {\n  - \"Chur\"\n  - \"Bad Ragaz\"\n}\n", file: "state.kdl", declarations: [Self.decl("weather-place", .record)])
        #expect(values["weather-place"] == nil)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .warning)
    }

    @Test("Abgeleitetes var wird nie gelesen")
    func derivedVarIsNeverRead() {
        let (values, diagnostics) = VarStateFile.read("launcher-results \"stale\"\n", file: "state.kdl", declarations: [Self.decl("launcher-results", .string, derived: true)])
        #expect(values.isEmpty)
        #expect(diagnostics.isEmpty)
    }

    @Test("Doppelter Knoten: letzter gilt, mit Warnung")
    func duplicateNodeUsesLastWithWarning() {
        let text = "dashboard-tab \"a\"\ndashboard-tab \"b\"\n"
        let (values, diagnostics) = VarStateFile.read(text, file: "state.kdl", declarations: [Self.decl("dashboard-tab", .string)])
        #expect(values["dashboard-tab"] == .string("b"))
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .warning)
    }

    @Test("type=any akzeptiert jeden Wert")
    func anyTypeAcceptsEverything() {
        let (values, diagnostics) = VarStateFile.read("flag 5\n", file: "state.kdl", declarations: [Self.decl("flag", .any)])
        #expect(diagnostics.isEmpty)
        #expect(values["flag"] == .number(5))
    }

    @Test("Leere Liste im Statusfile bleibt leer statt auf die Vorgabe zurueckzufallen")
    func emptyListStaysEmptyInsteadOfFallingBackToDefault() {
        let (values, diagnostics) = VarStateFile.read("pinned-toggles {\n}\n", file: "state.kdl", declarations: [Self.decl("pinned-toggles", .list)])
        #expect(diagnostics.isEmpty)
        #expect(values["pinned-toggles"] == .list([]))
    }

    @Test("50000 Listeneintraege werden im Zeitbudget gelesen")
    func largeListReadsWithinBudget() {
        var text = "big {\n"
        for index in 0..<50_000 {
            text += "  - \(index)\n"
        }
        text += "}\n"
        let start = Date()
        let (values, diagnostics) = VarStateFile.read(text, file: "state.kdl", declarations: [Self.decl("big", .list)])
        let elapsed = Date().timeIntervalSince(start)
        #expect(diagnostics.isEmpty)
        if case .list(let items)? = values["big"] {
            #expect(items.count == 50_000)
        } else {
            Issue.record("expected a list")
        }
        #expect(elapsed < 5 * ConfigLoaderTests.machineFactor)
    }
}

@Suite("VarStateFile writing")
struct VarStateFileWritingTests {
    @Test("Neue Datei aus leerem Text")
    func newFileFromEmptyText() throws {
        let updated = try VarStateFile.writing(["dashboard-tab": .string("media")], into: "", file: "state.kdl")
        #expect(updated.contains("dashboard-tab \"media\""))
    }

    @Test("Unveraenderter Wert bleibt byte-gleich")
    func unchangedValueStaysByteEqual() throws {
        let text = "dashboard-tab \"media\" // pinned\n"
        let updated = try VarStateFile.writing(["dashboard-tab": .string("media")], into: text, file: "state.kdl")
        #expect(updated == text)
    }

    @Test("Geaenderter Wert ersetzt nur den betroffenen Knoten")
    func changedValueReplacesOnlyThatNode() throws {
        let text = "// comment\ntheme-hint \"dark\"\ndashboard-tab \"media\"\n"
        let updated = try VarStateFile.writing(["dashboard-tab": .string("performance")], into: text, file: "state.kdl")
        #expect(updated.contains("// comment"))
        #expect(updated.contains("theme-hint \"dark\""))
        #expect(updated.contains("dashboard-tab \"performance\""))
        #expect(!updated.contains("\"media\""))
    }

    @Test("Neuer var wird angehaengt")
    func newVarIsAppended() throws {
        let text = "dashboard-tab \"media\"\n"
        let updated = try VarStateFile.writing(["sidebar-editing": .bool(false)], into: text, file: "state.kdl")
        #expect(updated.contains("dashboard-tab \"media\""))
        #expect(updated.contains("sidebar-editing #false"))
    }

    @Test("Unbekannter Knoten bleibt stehen")
    func unknownNodeStays() throws {
        let text = "legacy-thing 1\ndashboard-tab \"media\"\n"
        let updated = try VarStateFile.writing(["dashboard-tab": .string("performance")], into: text, file: "state.kdl")
        #expect(updated.contains("legacy-thing 1"))
    }

    @Test("Zahlen ohne Aenderung behalten ihren Originaltext")
    func unchangedNumberKeepsOriginalText() throws {
        let text = "launcher-selection 1e3\n"
        let updated = try VarStateFile.writing(["launcher-selection": .number(1000)], into: text, file: "state.kdl")
        #expect(updated.contains("1e3"))
    }

    @Test("NaN und unendlich kommen nie in die Datei")
    func nanAndInfiniteNeverReachTheFile() throws {
        let updated = try VarStateFile.writing(["value": .number(.nan)], into: "", file: "state.kdl")
        #expect(!updated.lowercased().contains("nan"))
        #expect(updated.contains("#null"))
    }

    @Test("CRLF bleibt erhalten")
    func crlfIsPreserved() throws {
        let text = "dashboard-tab \"media\"\r\n"
        let updated = try VarStateFile.writing(["dashboard-tab": .string("performance")], into: text, file: "state.kdl")
        #expect(updated.contains("\r\n"))
    }

    @Test("Nicht parsbare Datei wird nie ueberschrieben")
    func unparsableFileIsNeverOverwritten() {
        #expect(throws: (any Error).self) {
            try VarStateFile.writing(["a": .number(1)], into: "a \"unterminated", file: "state.kdl")
        }
    }

    @Test("50000 Listeneintraege, ein geaenderter Eintrag im Zeitbudget")
    func largeListWithOneChangedEntryWithinBudget() throws {
        var items: [Value] = []
        for index in 0..<50_000 {
            items.append(.number(Double(index)))
        }
        let text = try VarStateFile.writing(["big": .list(items)], into: "", file: "state.kdl")
        var changed = items
        changed[0] = .number(999)
        let start = Date()
        let updated = try VarStateFile.writing(["big": .list(changed)], into: text, file: "state.kdl")
        let elapsed = Date().timeIntervalSince(start)
        #expect(updated.contains("999"))
        #expect(elapsed < 5 * ConfigLoaderTests.machineFactor)
    }
}
