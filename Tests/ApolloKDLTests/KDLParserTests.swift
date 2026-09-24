import ApolloBase
import Testing
@testable import ApolloKDL

@Suite("KDL-Parser")
struct KDLParserTests {
    func parse(_ text: String) throws -> [KDLNode] {
        try KDLDocument.parse(text, file: "test.kdl").nodes
    }

    func parseError(_ text: String) -> KDLParseError? {
        do throws(KDLParseError) {
            _ = try KDLDocument.parse(text, file: "test.kdl")
            return nil
        } catch {
            return error
        }
    }

    @Test("Argumente und Properties behalten ihre Reihenfolge")
    func entries() throws {
        let node = try #require(try parse("node 1 \"two\" key=#true 3 key=#null other=(t)x").first)
        #expect(node.name == "node")
        #expect(node.arguments.map(\.scalar) == [.number(1, raw: "1"), .string("two"), .number(3, raw: "3")])
        #expect(node.properties.map(\.name) == ["key", "key", "other"])
        #expect(node.property("key")?.value.scalar == .null)
        #expect(node.property("other")?.value.annotation == "t")
        #expect(node.property("other")?.value.scalar == .string("x"))
    }

    @Test("alle Wertarten")
    func valueKinds() throws {
        let node = try #require(try parse("n \"s\" #\"r\\\"# 0x10 1.5e2 #true #false #null #inf #-inf bare").first)
        #expect(node.arguments.map(\.scalar) == [
            .string("s"), .string("r\\"), .number(16, raw: "0x10"), .number(150, raw: "1.5e2"),
            .bool(true), .bool(false), .null, .number(.infinity, raw: "#inf"), .number(-.infinity, raw: "#-inf"),
            .string("bare"),
        ])
        let nan = try #require(try parse("n #nan").first?.arguments.first)
        guard case .number(let value, let raw) = nan.scalar else {
            Issue.record("#nan muss eine Zahl sein")
            return
        }
        #expect(value.isNaN)
        #expect(raw == "#nan")
    }

    @Test("Kinderblöcke, leere Blöcke und Semikolons")
    func children() throws {
        let nodes = try parse("p {\n  a; b\n  c {}\n}\nq")
        #expect(nodes.map(\.name) == ["p", "q"])
        #expect(nodes[0].children?.map(\.name) == ["a", "b", "c"])
        #expect(nodes[0].children?[2].children == [])
        #expect(nodes[1].children == nil)
        #expect(try parse("n {foo;bar;baz}").first?.children?.count == 3)
    }

    @Test("Annotationen an Knoten und Werten bleiben erhalten")
    func annotations() throws {
        let node = try #require(try parse("(typ)node ( a )1 k=(\"x y\")2").first)
        #expect(node.annotation == "typ")
        #expect(node.arguments.first?.annotation == "a")
        #expect(node.property("k")?.value.annotation == "x y")
    }

    @Test("Slashdash an Knoten, Argumenten, Properties und Kinderblöcken")
    func slashdash() throws {
        let nodes = try parse("/- gone 1\nn /- 1 2 /- k=v /- { x } { y } /- { z }\nlast")
        #expect(nodes.map(\.name) == ["n", "last"])
        #expect(nodes[0].arguments.map(\.scalar) == [.number(2, raw: "2")])
        #expect(nodes[0].properties.isEmpty)
        #expect(nodes[0].children?.map(\.name) == ["y"])
        #expect(try parse("n 1 /-\n2 3").first?.arguments.count == 2)
        #expect(try parse("n 1 /- // c\n2 3").first?.arguments.map(\.scalar) == [.number(1, raw: "1"), .number(3, raw: "3")])
        #expect(try parse("/-\nnode 1\nnext").map(\.name) == ["next"])
    }

    @Test("Zeilenfortsetzung mit Backslash")
    func escline() throws {
        #expect(try parse("node \\\n  arg").first?.arguments.map(\.scalar) == [.string("arg")])
        #expect(try parse("node \\ // c\n  arg").first?.arguments.count == 1)
        #expect(try parse("a \\\n\nb").map(\.name) == ["a", "b"])
    }

    @Test("Syntaxfehler mit hilfreicher Meldung", arguments: [
        ("node\"a\"", "whitespace"),
        ("node true", "#true"),
        ("node inf", "#inf"),
        ("/- kdl-version 1\nnode", "KDL v2"),
        ("a }", "'}'"),
        ("}", "'}'"),
        ("a {", "never closed"),
        ("n .5", "0.5"),
        ("n 0x", "0x"),
        ("n \"\\/\"", "escape"),
        ("n \u{200E}x", "U+200E"),
        ("n \u{FEFF}x", "U+FEFF"),
        ("n { a } b", "children block"),
        ("n { a } { b }", "only one children block"),
        ("n /- /- 1", "another '/-'"),
        ("n 1 /-", "comments out"),
    ] as [(String, String)])
    func syntaxErrors(text: String, fragment: String) {
        let error = parseError(text)
        #expect(error != nil)
        #expect(error?.message.contains(fragment) == true, "\(String(describing: error?.message))")
        #expect(error?.span.file == "test.kdl")
    }

    @Test("Grammatik 2.0.0 ist streng", arguments: [
        "a;;", "node{}", "node \"a\"/-1", "node (t)key=1", "node key=", "(t)", "node ()1", "r\"legacy\"",
    ])
    func strictGrammar(text: String) {
        #expect(parseError(text) != nil)
    }

    @Test("Versionsmarke 2 und BOM am Anfang sind erlaubt")
    func versionAndBOM() throws {
        #expect(try parse("/- kdl-version 2\nnode").map(\.name) == ["node"])
        #expect(try parse("\u{FEFF}node").map(\.name) == ["node"])
        #expect(try parse("").isEmpty)
    }

    @Test("Ort eines Fehlers zählt Zeichen")
    func errorPosition() throws {
        let error = try #require(parseError("node \"\u{1F389}\" 0x\n"))
        #expect(error.span.start == SourcePosition(offset: 12, line: 1, column: 10))
        let crlf = try #require(parseError("a\r\nb \"\u{1F389}\" 1x"))
        #expect(crlf.span.start == SourcePosition(offset: 12, line: 2, column: 7))
    }

    @Test("Grösse: genau 1 MiB geht, ein Byte mehr nicht")
    func sizeLimit() throws {
        #expect(try parse(String(repeating: " ", count: KDLLimits.maxBytes)).isEmpty)
        let error = try #require(parseError(String(repeating: " ", count: KDLLimits.maxBytes + 1)))
        #expect(error.message.contains("1 MiB"))
    }

    @Test("Tiefe: 64 Ebenen gehen, 65 nicht")
    func depthLimit() throws {
        let ok = String(repeating: "n { ", count: 63) + "n" + String(repeating: " }", count: 63)
        var node = try #require(try parse(ok).first)
        var depth = 1
        while let child = node.children?.first {
            node = child
            depth += 1
        }
        #expect(depth == 64)
        let deep = String(repeating: "n { ", count: 64) + "n" + String(repeating: " }", count: 64)
        let error = try #require(parseError(deep))
        #expect(error.message.contains("64"))
    }

    @Test("leerer Kinderblock auf Ebene 64 ist erlaubt, ein Knoten auf Ebene 65 nicht")
    func depthLimitEmptyBlock() throws {
        let okEmptyBlock = String(repeating: "n { ", count: 63) + "n {}" + String(repeating: " }", count: 63)
        #expect(try parse(okEmptyBlock).first != nil)
        let deepNode = String(repeating: "n { ", count: 63) + "n { m }" + String(repeating: " }", count: 63)
        let error = try #require(parseError(deepNode))
        #expect(error.message.contains("64"))
    }

    @Test("nie geschlossene Konstrukte enden mit Fehler", arguments: [
        "/* x", "n /* /* */", "n #\"abc", "n \"abc", "n \"\"\"\nx", "n {", "n { a {",
    ])
    func unterminated(text: String) {
        #expect(parseError(text) != nil)
    }

    @Test("Orte von Knoten, Namen und Werten")
    func spans() throws {
        let node = try #require(try parse("  (t)name 12 k=\"v\" {\n  }\n").first)
        #expect(node.span.start == SourcePosition(offset: 2, line: 1, column: 3))
        #expect(node.span.end == SourcePosition(offset: 24, line: 2, column: 4))
        #expect(node.nameSpan.start.offset == 5)
        #expect(node.nameSpan.end.offset == 9)
        #expect(node.arguments[0].span.start.column == 11)
        #expect(node.arguments[0].span.end.column == 13)
        #expect(node.properties[0].span.start.column == 14)
        #expect(node.properties[0].value.span.start.column == 16)
        #expect(node.properties[0].span.end.column == 19)
        #expect(node.childrenBlock == 19..<24)
    }
}
