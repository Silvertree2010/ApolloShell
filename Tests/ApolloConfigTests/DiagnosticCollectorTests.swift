import Testing
import ApolloBase
@testable import ApolloConfig

@Suite("DiagnosticCollector")
struct DiagnosticCollectorTests {
    static func span(_ file: String, line: Int, column: Int = 1) -> SourceSpan {
        SourceSpan(file: file, start: SourcePosition(offset: 0, line: line, column: column), end: SourcePosition(offset: 0, line: line, column: column + 1))
    }

    @Test("Fehler vor Warnungen vor Notizen")
    func severityOrdering() {
        var collector = DiagnosticCollector()
        collector.add(Diagnostic(.note, "n", span: Self.span("a.kdl", line: 1)), stage: "schema")
        collector.add(Diagnostic(.error, "e", span: Self.span("a.kdl", line: 2)), stage: "schema")
        collector.add(Diagnostic(.warning, "w", span: Self.span("a.kdl", line: 3)), stage: "schema")
        let report = collector.finalize()
        #expect(report.diagnostics.map(\.severity) == [.error, .warning, .note])
    }

    @Test("Dateireihenfolge, dann Zeile, dann Spalte")
    func fileLineColumnOrdering() {
        var collector = DiagnosticCollector()
        collector.add(Diagnostic(.error, "first file", span: Self.span("a.kdl", line: 5)), stage: "schema")
        collector.add(Diagnostic(.error, "second file", span: Self.span("b.kdl", line: 1)), stage: "schema")
        collector.add(Diagnostic(.error, "first file earlier line", span: Self.span("a.kdl", line: 1)), stage: "schema")
        let report = collector.finalize()
        #expect(report.diagnostics.map(\.message) == ["first file earlier line", "first file", "second file"])
    }

    @Test("Diagnose ohne Spanne steht am Ende")
    func withoutSpanSortsLast() {
        var collector = DiagnosticCollector()
        collector.add(Diagnostic(.error, "with span", span: Self.span("a.kdl", line: 1)), stage: "schema")
        collector.add(Diagnostic(.error, "without span"), stage: "schema")
        let report = collector.finalize()
        #expect(report.diagnostics.map(\.message) == ["with span", "without span"])
    }

    @Test("Stabile Sortierung bei gleicher Position")
    func stableSortAtEqualPosition() {
        var collector = DiagnosticCollector()
        for index in 0..<5 {
            collector.add(Diagnostic(.error, "m\(index)", span: Self.span("a.kdl", line: 1)), stage: "schema")
        }
        let report = collector.finalize()
        #expect(report.diagnostics.map(\.message) == ["m0", "m1", "m2", "m3", "m4"])
    }

    @Test("Zaehler je Stufe")
    func stageCounts() {
        var collector = DiagnosticCollector()
        collector.add(Diagnostic(.error, "1"), stage: "schema")
        collector.add(Diagnostic(.error, "2"), stage: "schema")
        collector.add(Diagnostic(.warning, "3"), stage: "expressions")
        let report = collector.finalize()
        #expect(report.stageCounts["schema"] == 2)
        #expect(report.stageCounts["expressions"] == 1)
    }

    @Test("Genau 200 ergibt keine and-N-more Notiz")
    func exactlyTwoHundred() {
        var collector = DiagnosticCollector()
        for index in 0..<200 {
            collector.add(Diagnostic(.error, "e\(index)", span: Self.span("a.kdl", line: index + 1)), stage: "schema")
        }
        let report = collector.finalize()
        #expect(report.diagnostics.count == 200)
        #expect(!report.diagnostics.contains { $0.message.contains("more") })
    }

    @Test("201 Diagnosen ergeben and-1-more")
    func twoHundredOne() {
        var collector = DiagnosticCollector()
        for index in 0..<201 {
            collector.add(Diagnostic(.error, "e\(index)", span: Self.span("a.kdl", line: index + 1)), stage: "schema")
        }
        let report = collector.finalize()
        #expect(report.diagnostics.count == 201)
        #expect(report.diagnostics.last?.message == "and 1 more")
    }

    @Test("5000 Diagnosen bleiben korrekt gezaehlt und beschraenkt")
    func fiveThousand() {
        var collector = DiagnosticCollector()
        for index in 0..<5000 {
            collector.add(Diagnostic(.note, "n\(index)", span: Self.span("a.kdl", line: index + 1)), stage: "schema")
        }
        let report = collector.finalize()
        #expect(report.diagnostics.count == 201)
        #expect(report.diagnostics.last?.message == "and 4800 more")
        #expect(report.totalCounts[.note] == 5000)
    }

    @Test("Fehler hinter 300 Notizen bleibt sichtbar")
    func errorBehindManyNotesStaysVisible() {
        var collector = DiagnosticCollector()
        for index in 0..<300 {
            collector.add(Diagnostic(.note, "n\(index)", span: Self.span("a.kdl", line: index + 1)), stage: "schema")
        }
        collector.add(Diagnostic(.error, "the one error", span: Self.span("a.kdl", line: 301)), stage: "schema")
        let report = collector.finalize()
        #expect(report.diagnostics.first?.message == "the one error")
    }

    @Test("Kette wird als Notizen innerste zuerst angehaengt")
    func includeChainBecomesNotes() {
        var collector = DiagnosticCollector()
        let chain = [Self.span("b.kdl", line: 2), Self.span("a.kdl", line: 1)]
        collector.add(Diagnostic(.error, "boom", span: Self.span("c.kdl", line: 3)), stage: "schema", includeChain: chain)
        let report = collector.finalize()
        #expect(report.diagnostics[0].notes.map(\.message) == [
            "included from b.kdl:2:1",
            "included from a.kdl:1:1",
        ])
    }
}
