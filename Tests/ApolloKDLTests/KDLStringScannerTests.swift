import Testing
@testable import ApolloKDL

@Suite("KDL-Strings")
struct KDLStringScannerTests {
    func scan(_ text: String) throws -> String {
        var scanner = KDLStringScanner(source: KDLSource(text), index: 0)
        if text.hasPrefix("#") {
            return try scanner.scanRaw()
        }
        return try scanner.scanQuoted()
    }

    func endIndex(_ text: String) throws -> Int {
        var scanner = KDLStringScanner(source: KDLSource(text), index: 0)
        if text.hasPrefix("#") {
            _ = try scanner.scanRaw()
        } else {
            _ = try scanner.scanQuoted()
        }
        return scanner.index
    }

    @Test("gültige Strings", arguments: [
        ("\"\"", ""),
        ("\"\\\"\\\\\\b\\f\\n\\r\\t\\s\"", "\"\\\u{08}\u{0C}\n\r\t "),
        ("\"Hello \\      World\"", "Hello World"),
        ("\"a\\\n   b\"", "ab"),
        ("\"1\\\n\n\n2\"", "12"),
        ("\"Hello\\n\\      \\tWorld\"", "Hello\n\tWorld"),
        ("\"\\u{1F600}x\\u{a}\"", "\u{1F600}x\n"),
        ("\"tab\there \u{1F389} Gr\u{FC}\u{DF}e\"", "tab\there \u{1F389} Gr\u{FC}\u{DF}e"),
        ("#\"a\"b\"#", "a\"b"),
        ("#\"\\n\"#", "\\n"),
        ("#\"\"#", ""),
        ("##\"x\"#y\"##", "x\"#y"),
        ("###\"\"#\"##\"###", "\"#\"##"),
        ("\"\"\"\n    hey\n   everyone\n     how goes?\n  \"\"\"", "  hey\n everyone\n   how goes?"),
        ("\"\"\"\r\n  a\r\n  b\r\n  \"\"\"", "a\nb"),
        ("\"\"\"\n  \\r\\n\r\n  foo\r\n  \"\"\"", "\r\n\nfoo"),
        ("\"\"\"\n  foo \\\nbar\n  baz\n  \\   \"\"\"", "foo bar\nbaz"),
        ("\"\"\"\n  foo \\\nbar\n  baz\n\\   \"\"\"", "  foo bar\n  baz"),
        ("\"\"\"\n    a\n   \\\n\"\"\"", " a"),
        ("\"\"\"\n\"\"\"", ""),
        ("\"\"\"\n  \n\n  \"\"\"", "\n"),
        ("\"\"\"\n\\\"\"\"\n\"\"\"", "\"\"\""),
        ("\"\"\"\nthis has \"quotes\", twice\"\"\n\"\"\"", "this has \"quotes\", twice\"\""),
        ("\"\"\"\na\\\\ b\na\\\\\\ b\n\"\"\"", "a\\ b\na\\b"),
        ("#\"\"\"\n\"\"\"x\"\"\"\n\"\"\"#", "\"\"\"x\"\"\""),
        ("##\"\"\"\n#\"\"\"too few #\"\"\"#\n\"\"\"##", "#\"\"\"too few #\"\"\"#"),
    ] as [(String, String)])
    func valid(source: String, expected: String) throws {
        #expect(try scan(source) == expected)
    }

    @Test("ungültige Strings", arguments: [
        "\"never",
        "\"a\nb\"",
        "\"\\/\"",
        "\"\\u{D800}\"",
        "\"\\u{}\"",
        "\"\\u{1234567}\"",
        "\"\\u{110000}\"",
        "\"\\u41\"",
        "#\"never\"",
        "##\"foo\"#",
        "#\"a\nb\"#",
        "\"\"\"one line\"\"\"",
        "#\"\"\"one line\"\"\"#",
        "#\"\"\"#",
        "\"\"\"\n  foo\n  bar\\\n  \"\"\"",
        "\"\"\"\na\n   \\\n\"\"\"",
        "\"\"\"\n\\s x\n  y\n  \"\"\"",
        "\"\"\"\n    hey\n\t   how\n  \"\"\"",
        "\"\"\"\n    hey\n everyone\n  \"\"\"",
        "\"\"\"\n  a\n  b\"\"\"",
        "\"\"\"\n  a\n",
    ])
    func invalid(source: String) {
        #expect(throws: KDLSyntaxError.self) {
            try scan(source)
        }
    }

    @Test("Index steht hinter dem schliessenden Begrenzer")
    func endPositions() throws {
        #expect(try endIndex("\"ab\" rest") == 4)
        #expect(try endIndex("#\"a\"# rest") == 5)
        #expect(try endIndex("#\"a\"## rest") == 5)
        #expect(try endIndex("\"\"\"\n  x\n  \"\"\" rest") == 13)
        #expect(try endIndex("\"\u{1F389}\"") == 6)
    }

    @Test("roher Anfang wird erkannt")
    func rawStart() {
        #expect(KDLStringScanner.isRawStart(KDLSource("#\"x\"#"), at: 0))
        #expect(KDLStringScanner.isRawStart(KDLSource("###\"x\"###"), at: 0))
        #expect(!KDLStringScanner.isRawStart(KDLSource("#true"), at: 0))
        #expect(!KDLStringScanner.isRawStart(KDLSource("\"x\""), at: 0))
    }

    @Test("Fehler zeigt auf die Zeile mit der falschen Einrückung")
    func dedentErrorPosition() {
        do {
            _ = try scan("\"\"\"\n    hey\n x\n  \"\"\"")
            Issue.record("Fehler erwartet")
        } catch let error as KDLSyntaxError {
            #expect(error.start == 12)
        } catch {
            Issue.record("falscher Fehlertyp \(error)")
        }
    }
}
