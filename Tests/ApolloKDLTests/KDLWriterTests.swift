import Testing
@testable import ApolloKDL

@Suite("KDL-Writer")
struct KDLWriterTests {
    @Test("Einstellungen wie in settings.kdl")
    func settings() {
        let config = KDLNode(name: "config", arguments: [KDLValue(.string("apolloshell-default"))])
        #expect(KDLWriter.write(config, indent: "") == "config \"apolloshell-default\"")
        let updates = KDLNode(name: "updates", properties: [
            KDLProperty(name: "auto-check", value: KDLValue(.bool(true))),
            KDLProperty(name: "auto-install", value: KDLValue(.bool(false))),
        ])
        #expect(KDLWriter.write(updates, indent: "    ") == "    updates auto-check=#true auto-install=#false")
        #expect(KDLWriter.write(KDLNode(name: "theme", arguments: [KDLValue(.null)]), indent: "") == "theme #null")
    }

    @Test("Namen nur wenn nötig in Anführungszeichen", arguments: [
        ("auto-check", "auto-check"), ("with space", "\"with space\""), ("0node", "\"0node\""),
        ("true", "\"true\""), ("", "\"\""), ("a=b", "\"a=b\""), ("gr\u{FC}\u{DF}e", "gr\u{FC}\u{DF}e"),
        ("-1x", "\"-1x\""), ("\u{1F389}", "\u{1F389}"), (".5", "\".5\""),
    ] as [(String, String)])
    func names(name: String, expected: String) {
        #expect(KDLWriter.write(KDLNode(name: name), indent: "") == expected)
    }

    @Test("String-Werte immer in Anführungszeichen mit Escapes", arguments: [
        ("plain", "\"plain\""),
        ("a\"b\\c", "\"a\\\"b\\\\c\""),
        ("line\nbreak\r\ttab", "\"line\\nbreak\\r\\ttab\""),
        ("\u{08}\u{0C}", "\"\\b\\f\""),
        ("vt\u{0B}nel\u{85}ls\u{2028}", "\"vt\\u{b}nel\\u{85}ls\\u{2028}\""),
        ("bidi\u{200E}bom\u{FEFF}nul\u{0}", "\"bidi\\u{200e}bom\\u{feff}nul\\u{0}\""),
        ("\u{1F389} Gr\u{FC}\u{DF}e", "\"\u{1F389} Gr\u{FC}\u{DF}e\""),
        ("true", "\"true\""),
    ] as [(String, String)])
    func strings(value: String, expected: String) {
        let node = KDLNode(name: "n", arguments: [KDLValue(.string(value))])
        #expect(KDLWriter.write(node, indent: "") == "n " + expected)
    }

    @Test("Zahlen: Originaltext, wenn er passt, sonst kurze Form", arguments: [
        (16.0, "0x10", "0x10"), (16, "17", "16"), (16, "", "16"), (3, "", "3"), (-2, "", "-2"), (0.5, "", "0.5"),
        (1e20, "", "1e+20"), (.infinity, "", "#inf"), (-.infinity, "", "#-inf"), (1000, "1_000", "1_000"),
        (.infinity, "#inf", "#inf"), (2, "nonsense", "2"),
    ] as [(Double, String, String)])
    func numbers(value: Double, raw: String, expected: String) {
        let node = KDLNode(name: "n", arguments: [KDLValue(.number(value, raw: raw))])
        #expect(KDLWriter.write(node, indent: "") == "n " + expected)
    }

    @Test("NaN wird #nan")
    func nan() {
        let node = KDLNode(name: "n", arguments: [KDLValue(.number(.nan, raw: ""))])
        #expect(KDLWriter.write(node, indent: "") == "n #nan")
    }

    @Test("Kinder mit Einrückung, leere Kinder als {}")
    func children() {
        let node = KDLNode(name: "panel", arguments: [KDLValue(.string("bar"))], children: [
            KDLNode(name: "text", arguments: [KDLValue(.string("hi"))]),
            KDLNode(name: "row", children: [KDLNode(name: "x")]),
            KDLNode(name: "empty", children: []),
        ])
        let expected = "  panel \"bar\" {\n      text \"hi\"\n      row {\n          x\n      }\n      empty {}\n  }"
        #expect(KDLWriter.write(node, indent: "  ") == expected)
        let tabbed = KDLNode(name: "r", children: [KDLNode(name: "x")])
        #expect(KDLWriter.write(tabbed, indent: "", indentUnit: "\t") == "r {\n\tx\n}")
        #expect(KDLWriter.render(tabbed, indent: "  ", indentUnit: "  ", newline: "\r\n") == "r {\r\n    x\r\n  }")
    }

    @Test("Annotationen an Knoten und Werten")
    func annotations() {
        var node = KDLNode(
            name: "n",
            arguments: [KDLValue(.number(1, raw: "1"), annotation: "u8")],
            properties: [KDLProperty(name: "k", value: KDLValue(.string("v"), annotation: "a b"))]
        )
        node.annotation = "typ"
        #expect(KDLWriter.write(node, indent: "") == "(typ)n (u8)1 k=(\"a b\")\"v\"")
    }

    @Test("Geschriebener Text liest sich zum selben Knoten zurück")
    func roundTrip() throws {
        var annotated = KDLNode(name: "(odd)", arguments: [KDLValue(.number(.nan, raw: ""))])
        annotated.annotation = "t"
        let nodes = [
            KDLNode(name: "long", arguments: [KDLValue(.string(String(repeating: "\u{1F389}x\t", count: 10_000)))]),
            KDLNode(
                name: "all",
                arguments: [
                    KDLValue(.string("\u{0}\u{7F}\u{200F}\u{2066}\u{0B}\u{0C}\r\n\u{85}")),
                    KDLValue(.bool(false)), KDLValue(.null), KDLValue(.number(-0.25, raw: "")),
                ],
                properties: [
                    KDLProperty(name: "dup", value: KDLValue(.number(1, raw: "1"))),
                    KDLProperty(name: "dup", value: KDLValue(.number(2, raw: "0b10"))),
                ]
            ),
            KDLNode(name: "", children: [
                KDLNode(name: "#hash", children: []),
                KDLNode(name: "x y", children: [KDLNode(name: "z")]),
            ]),
            annotated,
        ]
        for node in nodes {
            let text = KDLWriter.write(node, indent: "\t")
            let parsed = try KDLDocument.parse(text, file: "w.kdl")
            #expect(parsed.nodes.count == 1)
            #expect(parsed.nodes.first?.isEquivalent(to: node) == true, "\(text)")
        }
    }
}
