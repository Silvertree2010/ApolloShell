import Testing
import Foundation
import ApolloBase
import ApolloKDL
@testable import ApolloConfig

@Suite("Diagnosen als Golden Files")
struct DiagnosticGoldenTests {
    static func node(named name: String, in document: KDLDocument) -> KDLNode? {
        func search(_ nodes: [KDLNode]) -> KDLNode? {
            for node in nodes {
                if node.name == name { return node }
                if let children = node.children, let found = search(children) {
                    return found
                }
            }
            return nil
        }
        return search(document.nodes)
    }

    @Test("Vorschlag fuer einen Tippfehler")
    func suggestion() throws {
        let path = DiagnosticGolden.file("vorschlag", "sidebar.kdl")
        let text = try DiskFileSystem().read(URL(fileURLWithPath: path))
        let document = try KDLDocument.parse(text, file: path)
        let node = try #require(Self.node(named: "on-clik", in: document))
        let suggestion = Suggestion.closest(to: "on-clik", among: ["on-click", "on-hover"])
        var collector = DiagnosticCollector()
        collector.add(
            Diagnostic(.error, "unknown handler 'on-clik' on 'button'", span: node.nameSpan, help: suggestion.map { "did you mean '\($0)'?" }),
            stage: "schema"
        )
        DiagnosticGolden.verify("vorschlag", diagnostics: collector.finalize().diagnostics)
    }

    @Test("Kette ueber drei Ebenen")
    func chainOverThreeLevels() throws {
        let disk = DiskFileSystem()
        let aPath = DiagnosticGolden.file("kette-drei-ebenen", "a.kdl")
        let bPath = DiagnosticGolden.file("kette-drei-ebenen", "b.kdl")
        let cPath = DiagnosticGolden.file("kette-drei-ebenen", "c.kdl")
        let aDocument = try KDLDocument.parse(try disk.read(URL(fileURLWithPath: aPath)), file: aPath)
        let bDocument = try KDLDocument.parse(try disk.read(URL(fileURLWithPath: bPath)), file: bPath)
        let cDocument = try KDLDocument.parse(try disk.read(URL(fileURLWithPath: cPath)), file: cPath)
        let includeInA = try #require(Self.node(named: "include", in: aDocument))
        let includeInB = try #require(Self.node(named: "include", in: bDocument))
        let brokenNode = try #require(Self.node(named: "panel", in: cDocument))
        var collector = DiagnosticCollector()
        collector.add(
            Diagnostic(.error, "unknown property 'surprise' on 'panel'", span: brokenNode.span),
            stage: "schema",
            includeChain: [includeInA.span, includeInB.span]
        )
        DiagnosticGolden.verify("kette-drei-ebenen", diagnostics: collector.finalize().diagnostics)
    }

    @Test("Genau 200 Diagnosen brauchen kein and-N-more")
    func exactlyTwoHundred() {
        var collector = DiagnosticCollector()
        for index in 0..<200 {
            collector.add(Diagnostic(.error, "problem \(index)", span: SourceSpan(file: "many.kdl", start: SourcePosition(offset: 0, line: index + 1, column: 1), end: SourcePosition(offset: 1, line: index + 1, column: 2))), stage: "schema")
        }
        DiagnosticGolden.verify("genau-200", diagnostics: collector.finalize().diagnostics)
    }

    @Test("201 Diagnosen zeigen and-1-more")
    func twoHundredOne() {
        var collector = DiagnosticCollector()
        for index in 0..<201 {
            collector.add(Diagnostic(.error, "problem \(index)", span: SourceSpan(file: "many.kdl", start: SourcePosition(offset: 0, line: index + 1, column: 1), end: SourcePosition(offset: 1, line: index + 1, column: 2))), stage: "schema")
        }
        DiagnosticGolden.verify("201", diagnostics: collector.finalize().diagnostics)
    }

    @Test("5000 Diagnosen bleiben auf 200 plus and-N-more begrenzt")
    func fiveThousand() {
        var collector = DiagnosticCollector()
        for index in 0..<5000 {
            collector.add(Diagnostic(.note, "problem \(index)", span: SourceSpan(file: "many.kdl", start: SourcePosition(offset: 0, line: index + 1, column: 1), end: SourcePosition(offset: 1, line: index + 1, column: 2))), stage: "schema")
        }
        DiagnosticGolden.verify("5000", diagnostics: collector.finalize().diagnostics)
    }

    @Test("Ein Fehler hinter 300 Notizen bleibt sichtbar")
    func errorBehindManyNotesStaysVisible() {
        var collector = DiagnosticCollector()
        for index in 0..<300 {
            collector.add(Diagnostic(.note, "note \(index)", span: SourceSpan(file: "many.kdl", start: SourcePosition(offset: 0, line: index + 1, column: 1), end: SourcePosition(offset: 1, line: index + 1, column: 2))), stage: "schema")
        }
        collector.add(Diagnostic(.error, "the one error", span: SourceSpan(file: "many.kdl", start: SourcePosition(offset: 0, line: 301, column: 1), end: SourcePosition(offset: 1, line: 301, column: 2))), stage: "schema")
        DiagnosticGolden.verify("fehler-hinter-notizen", diagnostics: collector.finalize().diagnostics)
    }

    @Test("Diagnose ohne Spanne")
    func withoutSpan() {
        var collector = DiagnosticCollector()
        collector.add(Diagnostic(.error, "the expansion budget was exceeded"), stage: "expand")
        DiagnosticGolden.verify("ohne-spanne", diagnostics: collector.finalize().diagnostics)
    }
}
