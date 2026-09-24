import Testing
@testable import ApolloKDL

@Suite("KDL-Editor")
struct KDLEditorTests {
    static let lines = [
        "// Einstellungen \u{1F39B}\u{FE0F}",
        "config \"apolloshell-default\"",
        "",
        "theme \"Afterglow\" // Lieblingsthema",
        "\tupdates auto-check=#true auto-install=#false",
        "panel \"gr\u{FC}\u{DF}e\" {",
        "    /* erste Zeile */",
        "    text \"Hallo \u{1F44B} Welt\" size=12",
        "\tlabel \"Tab-Einr\u{FC}ckung\"; icon \"\u{1F1E8}\u{1F1ED}\"",
        "}",
        "editor \"code -g {file}:{line}:{column}\"",
    ]

    static let widget = KDLNode(name: "widget", arguments: [KDLValue(.number(1, raw: "1"))])

    static func file(_ lines: [String], newline: String = "\n") -> String {
        lines.joined(separator: newline)
    }

    static func editor(_ text: String) throws -> KDLEditor {
        KDLEditor(try KDLDocument.parse(text, file: "settings.kdl"))
    }

    func expectText(_ editor: KDLEditor, _ expected: String) throws {
        #expect(editor.text == expected)
        #expect(editor.document.text == editor.text)
        let reparsed = try KDLDocument.parse(editor.text, file: "settings.kdl")
        #expect(KDLNode.areEquivalent(reparsed.nodes, editor.document.nodes))
    }

    @Test("Ersetzen behält Kommentar dahinter")
    func replaceKeepsTrailingComment() throws {
        var editor = try Self.editor(Self.file(Self.lines))
        try editor.replace(at: [1], with: KDLNode(name: "theme", arguments: [KDLValue(.string("Nord"))]))
        var expected = Self.lines
        expected[3] = "theme \"Nord\" // Lieblingsthema"
        try expectText(editor, Self.file(expected))
    }

    @Test("Ersetzen behält Tab-Einrückung")
    func replaceKeepsIndent() throws {
        var editor = try Self.editor(Self.file(Self.lines))
        let updates = KDLNode(name: "updates", properties: [
            KDLProperty(name: "auto-check", value: KDLValue(.bool(true))),
            KDLProperty(name: "auto-install", value: KDLValue(.bool(true))),
        ])
        try editor.replace(at: [2], with: updates)
        var expected = Self.lines
        expected[4] = "\tupdates auto-check=#true auto-install=#true"
        try expectText(editor, Self.file(expected))
    }

    @Test("Ersetzen eines Blocks schreibt den neuen Block")
    func replaceBlock() throws {
        var editor = try Self.editor(Self.file(Self.lines))
        let panel = KDLNode(name: "panel", arguments: [KDLValue(.string("neu"))], children: [
            KDLNode(name: "text", arguments: [KDLValue(.string("\u{E4}"))]),
        ])
        try editor.replace(at: [3], with: panel)
        var expected = Self.lines
        expected.replaceSubrange(5...9, with: ["panel \"neu\" {", "    text \"\u{E4}\"", "}"])
        try expectText(editor, Self.file(expected))
    }

    @Test("Entfernen einer eigenen Zeile samt Umbruch")
    func removeOwnLine() throws {
        var editor = try Self.editor(Self.file(Self.lines))
        try editor.remove(at: [0])
        var expected = Self.lines
        expected.remove(at: 1)
        try expectText(editor, Self.file(expected))
    }

    @Test("Entfernen auf geteilter Zeile, vorne und hinten")
    func removeShared() throws {
        var first = try Self.editor(Self.file(Self.lines))
        try first.remove(at: [3, 1])
        var expectedFirst = Self.lines
        expectedFirst[8] = "\ticon \"\u{1F1E8}\u{1F1ED}\""
        try expectText(first, Self.file(expectedFirst))

        var last = try Self.editor(Self.file(Self.lines))
        try last.remove(at: [3, 2])
        var expectedLast = Self.lines
        expectedLast[8] = "\tlabel \"Tab-Einr\u{FC}ckung\"; "
        try expectText(last, Self.file(expectedLast))
    }

    @Test("Entfernen des letzten Kindes lässt einen leeren Block", arguments: [
        ("p {\n    x 1\n}", "p {\n}"),
        ("p {\r\n    x 1\r\n}", "p {\r\n}"),
        ("p {\n\tx 1\n}", "p {\n}"),
        ("p {\n    /* c */\n    x 1\n}", "p {\n    /* c */\n}"),
        ("  p {\n      x 1\n  }\n", "  p {\n  }\n"),
    ] as [(String, String)])
    func removeLastChild(text: String, expected: String) throws {
        var editor = try Self.editor(text)
        let parent = editor.document.nodes.count - 1
        try editor.remove(at: [parent, 0])
        try expectText(editor, expected)
    }

    @Test("Einfügen nach einem Knoten auf eigener Zeile")
    func insertAfterOwnLine() throws {
        var editor = try Self.editor(Self.file(Self.lines))
        try editor.insert(Self.widget, after: [3, 0])
        var expected = Self.lines
        expected.insert("    widget 1", at: 8)
        try expectText(editor, Self.file(expected))
    }

    @Test("Einfügen nach dem letzten Knoten ohne Umbruch am Dateiende")
    func insertAfterLast() throws {
        var editor = try Self.editor(Self.file(Self.lines))
        try editor.insert(Self.widget, after: [4])
        try expectText(editor, Self.file(Self.lines + ["widget 1"]))
    }

    @Test("Einfügen an Index 0 setzt vor die Zeile des ersten Kindes")
    func insertAtStartOfChildren() throws {
        var editor = try Self.editor(Self.file(Self.lines))
        try editor.insert(Self.widget, intoChildrenOf: [3], at: 0)
        var expected = Self.lines
        expected.insert("    widget 1", at: 7)
        try expectText(editor, Self.file(expected))
    }

    @Test("Einfügen an Index 0 der obersten Ebene bleibt unter dem Kopfkommentar")
    func insertAtTopStart() throws {
        var editor = try Self.editor(Self.file(Self.lines))
        try editor.insert(Self.widget, intoChildrenOf: nil, at: 0)
        var expected = Self.lines
        expected.insert("widget 1", at: 1)
        try expectText(editor, Self.file(expected))
    }

    @Test("Einfügen am Ende einer geteilten Zeile")
    func insertAtEndOfSharedLine() throws {
        var editor = try Self.editor(Self.file(Self.lines))
        try editor.insert(Self.widget, intoChildrenOf: [3], at: 3)
        var expected = Self.lines
        expected[8] = "\tlabel \"Tab-Einr\u{FC}ckung\"; icon \"\u{1F1E8}\u{1F1ED}\"; widget 1"
        try expectText(editor, Self.file(expected))
    }

    @Test("Einfügen in einen Knoten ohne Kinderblock legt einen an")
    func insertIntoNodeWithoutChildren() throws {
        var editor = try Self.editor(Self.file(Self.lines))
        try editor.insert(Self.widget, intoChildrenOf: [0], at: 0)
        var expected = Self.lines
        expected[1] = "config \"apolloshell-default\" {"
        expected.insert(contentsOf: ["    widget 1", "}"], at: 2)
        try expectText(editor, Self.file(expected))
    }

    @Test("CRLF-Datei bekommt CRLF")
    func crlfFile() throws {
        var editor = try Self.editor(Self.file(Self.lines, newline: "\r\n"))
        try editor.insert(Self.widget, after: [3, 0])
        var expected = Self.lines
        expected.insert("    widget 1", at: 8)
        try expectText(editor, Self.file(expected, newline: "\r\n"))
        try editor.remove(at: [0])
        expected.remove(at: 1)
        try expectText(editor, Self.file(expected, newline: "\r\n"))
    }

    @Test("leere Kinderblöcke", arguments: [
        ("p {\n}", "p {\n    x 1\n}"),
        ("p { }", "p {\n    x 1\n}"),
        ("p {}", "p {\n    x 1\n}"),
        ("p { /* c */ }", "p {\n    x 1\n /* c */ }"),
        ("  p {}\n", "  p {\n      x 1\n  }\n"),
        ("q {\n\ty\n}\np", "q {\n\ty\n}\np {\n\tx 1\n}"),
    ] as [(String, String)])
    func emptyBlocks(text: String, expected: String) throws {
        var editor = try Self.editor(text)
        let parent = editor.document.nodes.count - 1
        try editor.insert(KDLNode(name: "x", arguments: [KDLValue(.number(1, raw: "1"))]), intoChildrenOf: [parent], at: 0)
        try expectText(editor, expected)
    }

    @Test("Dokument ohne Knoten", arguments: [
        ("", "x 1\n"),
        ("// nur Kommentar", "// nur Kommentar\nx 1\n"),
        ("// k\n", "// k\nx 1\n"),
    ] as [(String, String)])
    func emptyDocument(text: String, expected: String) throws {
        var editor = try Self.editor(text)
        try editor.insert(KDLNode(name: "x", arguments: [KDLValue(.number(1, raw: "1"))]), intoChildrenOf: nil, at: 0)
        try expectText(editor, expected)
    }

    @Test("BOM bleibt vorne stehen")
    func bomFile() throws {
        var removing = try Self.editor("\u{FEFF}a 1\nb 2\n")
        try removing.remove(at: [0])
        try expectText(removing, "\u{FEFF}b 2\n")
        var inserting = try Self.editor("\u{FEFF}a 1\nb 2\n")
        try inserting.insert(Self.widget, intoChildrenOf: nil, at: 0)
        try expectText(inserting, "\u{FEFF}widget 1\na 1\nb 2\n")
    }

    @Test("Bytes ausserhalb des Bereichs bleiben gleich, auch bei langen Strings und Emoji")
    func unchangedOutside() throws {
        let long = String(repeating: "\u{1F389}\u{E4}", count: 5_000)
        let text = "a \"" + long + "\"\n\tb 1 // \u{1F44B}\nc \"" + long + "\"\n"
        var editor = try Self.editor(text)
        let old = editor.document.nodes[1]
        try editor.replace(at: [1], with: KDLNode(name: "b", arguments: [KDLValue(.number(2, raw: "2"))]))
        let before = Array(text.utf8)
        let after = Array(editor.text.utf8)
        let start = old.span.start.offset
        let tailLength = before.count - old.span.end.offset
        #expect(after.prefix(start).elementsEqual(before.prefix(start)))
        #expect(after.suffix(tailLength).elementsEqual(before.suffix(tailLength)))
        try expectText(editor, "a \"" + long + "\"\n\tb 2 // \u{1F44B}\nc \"" + long + "\"\n")
    }

    @Test("mehrere Operationen hintereinander nutzen die neuen Orte")
    func sequence() throws {
        var editor = try Self.editor(Self.file(Self.lines))
        try editor.remove(at: [0])
        try editor.insert(Self.widget, after: [0])
        try editor.remove(at: [3, 2])
        var expected = Self.lines
        expected.remove(at: 1)
        expected.insert("widget 1", at: 3)
        expected[8] = "\tlabel \"Tab-Einr\u{FC}ckung\"; "
        try expectText(editor, Self.file(expected))
    }

    @Test("ungültige Pfade und Indizes ändern nichts")
    func invalidPaths() throws {
        var editor = try Self.editor(Self.file(Self.lines))
        let before = editor.text
        var failures = 0
        do { try editor.remove(at: [9]) } catch { failures += 1 }
        do { try editor.replace(at: [3, 7], with: Self.widget) } catch { failures += 1 }
        do { try editor.insert(Self.widget, after: []) } catch { failures += 1 }
        do { try editor.insert(Self.widget, intoChildrenOf: [3], at: 4) } catch { failures += 1 }
        do { try editor.insert(Self.widget, intoChildrenOf: nil, at: -1) } catch { failures += 1 }
        #expect(failures == 5)
        #expect(editor.text == before)
    }

    @Test("ein Ergebnis, das nicht der Erwartung entspricht, wird verworfen")
    func rejectsMismatch() throws {
        var editor = try Self.editor(Self.file(Self.lines))
        let before = editor.text
        let nodes = editor.document.nodes
        var failures = 0
        do { try editor.commit(replacing: 0..<0, with: "", expected: []) } catch { failures += 1 }
        do { try editor.commit(replacing: 0..<0, with: "{", expected: nodes) } catch { failures += 1 }
        #expect(failures == 2)
        #expect(editor.text == before)
        #expect(KDLNode.areEquivalent(editor.document.nodes, nodes))
    }
}
