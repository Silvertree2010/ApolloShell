import ApolloBase
import Testing
@testable import ApolloKDL

@Suite("KDL: Positionen und Zeilenbereiche")
struct KDLPositionTests {
    static let sample = [
        "// Kopf \u{1F389}\n",
        "panel \"bar\" {\n",
        "\ttext \"Gr\u{FC}\u{DF}e Mu\u{308}ller \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\" size=12\n",
        "\tlabel \"\"\"\n",
        "\t\tzwei\n",
        "\t\tZeilen\n",
        "\t\t\"\"\"\n",
        "    /* Kommentar */ icon \"\u{1F1E8}\u{1F1ED}\"\r\n",
        "}\n",
        "\u{FC}n\u{EF}c\u{F6}d\u{E9}-n\u{E4}me 1; zweiter 2\n",
    ].joined()

    struct Reference: Sendable {
        let path: [Int]
        let name: String
        let start: SourcePosition
        let end: SourcePosition
        let lineRange: Range<Int>
    }

    static let references = [
        Reference(path: [0], name: "panel",
                  start: SourcePosition(offset: 13, line: 2, column: 1), end: SourcePosition(offset: 150, line: 9, column: 2),
                  lineRange: 13..<151),
        Reference(path: [0, 0], name: "text",
                  start: SourcePosition(offset: 28, line: 3, column: 2), end: SourcePosition(offset: 78, line: 3, column: 31),
                  lineRange: 27..<79),
        Reference(path: [0, 1], name: "label",
                  start: SourcePosition(offset: 80, line: 4, column: 2), end: SourcePosition(offset: 111, line: 7, column: 6),
                  lineRange: 79..<112),
        Reference(path: [0, 2], name: "icon",
                  start: SourcePosition(offset: 132, line: 8, column: 21), end: SourcePosition(offset: 147, line: 8, column: 29),
                  lineRange: 132..<147),
        Reference(path: [1], name: "\u{FC}n\u{EF}c\u{F6}d\u{E9}-n\u{E4}me",
                  start: SourcePosition(offset: 151, line: 10, column: 1), end: SourcePosition(offset: 170, line: 10, column: 15),
                  lineRange: 151..<172),
        Reference(path: [2], name: "zweiter",
                  start: SourcePosition(offset: 172, line: 10, column: 17), end: SourcePosition(offset: 181, line: 10, column: 26),
                  lineRange: 172..<181),
    ]

    static func node(at path: [Int], in nodes: [KDLNode]) -> KDLNode? {
        guard let first = path.first, nodes.indices.contains(first) else { return nil }
        if path.count == 1 { return nodes[first] }
        return node(at: Array(path.dropFirst()), in: nodes[first].children ?? [])
    }

    static func slice(_ text: String, _ range: Range<Int>) -> String {
        String(decoding: Array(text.utf8)[range], as: UTF8.self)
    }

    @Test("Zeile, Spalte und Zeilenbereich jedes Knotens stimmen mit der Referenzliste")
    func referenceList() throws {
        let document = try KDLDocument.parse(Self.sample, file: "beispiel.kdl")
        for reference in Self.references {
            let node = try #require(Self.node(at: reference.path, in: document.nodes))
            #expect(node.name == reference.name)
            #expect(node.span.start == reference.start, "\(reference.name)")
            #expect(node.span.end == reference.end, "\(reference.name)")
            #expect(node.lineRange == reference.lineRange, "\(reference.name)")
            #expect(node.span.file == "beispiel.kdl")
        }
    }

    @Test("Zeilenbereiche enthalten Einrückung, Kommentare und Umbruch")
    func referenceSlices() throws {
        let document = try KDLDocument.parse(Self.sample, file: "beispiel.kdl")
        let label = try #require(Self.node(at: [0, 1], in: document.nodes))
        #expect(Self.slice(Self.sample, label.lineRange) == "\tlabel \"\"\"\n\t\tzwei\n\t\tZeilen\n\t\t\"\"\"\n")
        let icon = try #require(Self.node(at: [0, 2], in: document.nodes))
        #expect(Self.slice(Self.sample, icon.lineRange) == "icon \"\u{1F1E8}\u{1F1ED}\"")
        let first = try #require(Self.node(at: [1], in: document.nodes))
        #expect(Self.slice(Self.sample, first.lineRange) == "\u{FC}n\u{EF}c\u{F6}d\u{E9}-n\u{E4}me 1; ")
        #expect(label.arguments.first?.scalar == .string("zwei\nZeilen"))
    }

    @Test("Orte von Argumenten, Properties und Namen")
    func valueSpans() throws {
        let document = try KDLDocument.parse(Self.sample, file: "beispiel.kdl")
        let text = try #require(Self.node(at: [0, 0], in: document.nodes))
        #expect(text.nameSpan.start == SourcePosition(offset: 28, line: 3, column: 2))
        #expect(text.nameSpan.end == SourcePosition(offset: 32, line: 3, column: 6))
        #expect(text.arguments[0].span.start == SourcePosition(offset: 33, line: 3, column: 7))
        #expect(text.arguments[0].span.end == SourcePosition(offset: 70, line: 3, column: 23))
        #expect(text.properties[0].span.start == SourcePosition(offset: 71, line: 3, column: 24))
        #expect(text.properties[0].value.span.start == SourcePosition(offset: 76, line: 3, column: 29))
        #expect(text.properties[0].span.end == SourcePosition(offset: 78, line: 3, column: 31))
        let label = try #require(Self.node(at: [0, 1], in: document.nodes))
        #expect(label.arguments[0].span.start == SourcePosition(offset: 86, line: 4, column: 8))
        #expect(label.arguments[0].span.end == SourcePosition(offset: 111, line: 7, column: 6))
        let zweiter = try #require(Self.node(at: [2], in: document.nodes))
        #expect(zweiter.arguments[0].span.start == SourcePosition(offset: 180, line: 10, column: 25))
    }

    @Test("Zeilenbereiche bei Terminatoren, Kommentaren, BOM und geteilten Zeilen", arguments: [
        ("a;\nb", [0], 0..<3),
        ("a // c\nb", [0], 0..<7),
        ("a /* c */\nb", [0], 0..<10),
        ("a", [0], 0..<1),
        ("  a  ", [0], 0..<5),
        ("\u{FEFF}a\nb", [0], 3..<5),
        ("a; b", [0], 0..<3),
        ("a; b", [1], 3..<4),
        ("a;b", [0], 0..<2),
        ("a\u{85}b", [0], 0..<3),
        ("a\r\nb", [0], 0..<3),
        ("x; y // c\nz", [1], 3..<9),
        ("p { x }", [0, 0], 4..<6),
        ("p {\n    x\n}", [0, 0], 4..<10),
        ("p {\n    x\n}", [0], 0..<11),
        ("a \\\n  1\nb", [0], 0..<8),
        ("/* c */ a\nb", [0], 8..<9),
        ("\ta \"\"\"\n\tx\n\t\"\"\"\nb", [0], 0..<15),
    ] as [(String, [Int], Range<Int>)])
    func lineRanges(text: String, path: [Int], expected: Range<Int>) throws {
        let document = try KDLDocument.parse(text, file: "z.kdl")
        let node = try #require(Self.node(at: path, in: document.nodes))
        #expect(node.lineRange == expected)
    }

    @Test("Spalte hinter einem String mit 100 000 Zeichen")
    func longString() throws {
        let text = "a \"" + String(repeating: "x", count: 100_000) + "\"; b\n"
        let document = try KDLDocument.parse(text, file: "lang.kdl")
        #expect(document.nodes[0].arguments[0].span.end == SourcePosition(offset: 100_004, line: 1, column: 100_005))
        #expect(document.nodes[1].span.start == SourcePosition(offset: 100_006, line: 1, column: 100_007))
    }

    @Test("Lage eines Knotens für den Editor")
    func layout() {
        let source = KDLSource("\tlabel 1; icon 2 // c\n")
        let label = KDLLineRange.layout(in: source, start: 1, end: 8)
        #expect(label.lineIndent == "\t")
        #expect(label.indentOnly)
        #expect(!label.ownLine)
        #expect(label.tail == .sameLine(10))
        let icon = KDLLineRange.layout(in: source, start: 10, end: 16)
        #expect(icon.lineIndent == "\t")
        #expect(!icon.indentOnly)
        #expect(icon.tail == .lineEnd(contentEnd: 21, afterBreak: 22))
        #expect(icon.range == 10..<21)
    }
}
