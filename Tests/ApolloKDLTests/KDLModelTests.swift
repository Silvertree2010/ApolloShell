import ApolloBase
import Testing
@testable import ApolloKDL

@Suite("KDL-Modell")
struct KDLModelTests {
    @Test("Standardwerte eines neuen Knotens")
    func defaults() {
        let node = KDLNode(name: "panel")
        #expect(node.annotation == nil)
        #expect(node.arguments.isEmpty)
        #expect(node.properties.isEmpty)
        #expect(node.children == nil)
        #expect(node.span.isSynthetic)
        #expect(node.nameSpan.isSynthetic)
        #expect(node.lineRange == 0..<0)
        #expect(node.childrenBlock == nil)
    }

    @Test("property liefert bei doppelten Namen die rechte, alle bleiben erhalten")
    func rightmostProperty() {
        let node = KDLNode(name: "n", properties: [
            KDLProperty(name: "a", value: KDLValue(.number(1, raw: "1"))),
            KDLProperty(name: "b", value: KDLValue(.bool(true))),
            KDLProperty(name: "a", value: KDLValue(.number(2, raw: "2"))),
        ])
        #expect(node.property("a")?.value.scalar == .number(2, raw: "2"))
        #expect(node.property("c") == nil)
        #expect(node.properties.map(\.name) == ["a", "b", "a"])
    }

    @Test("Äquivalenz vergleicht Zahlen nach Wert und ignoriert Orte")
    func numbers() {
        let span = SourceSpan(
            file: "a.kdl",
            start: SourcePosition(offset: 1, line: 1, column: 2),
            end: SourcePosition(offset: 5, line: 1, column: 6)
        )
        let located = KDLValue(.number(16, raw: "0x10"), span: span)
        #expect(located.isEquivalent(to: KDLValue(.number(16, raw: "16"))))
        #expect(KDLValue(.number(.nan, raw: "#nan")).isEquivalent(to: KDLValue(.number(.nan, raw: ""))))
        #expect(!KDLValue(.number(1, raw: "1")).isEquivalent(to: KDLValue(.string("1"))))
        #expect(!KDLValue(.null).isEquivalent(to: KDLValue(.bool(false))))
        #expect(!KDLValue(.string("x"), annotation: "t").isEquivalent(to: KDLValue(.string("x"))))
    }

    @Test("Äquivalenz unterscheidet Kinder nil und leer, Reihenfolge und Annotation")
    func structure() {
        let base = KDLNode(name: "p", arguments: [KDLValue(.string("a")), KDLValue(.string("b"))])
        var withEmptyChildren = base
        withEmptyChildren.children = []
        var swapped = base
        swapped.arguments.reverse()
        var annotated = base
        annotated.annotation = "t"
        var moved = base
        moved.lineRange = 4..<9
        moved.childrenBlock = 5..<7
        #expect(base.isEquivalent(to: moved))
        #expect(!base.isEquivalent(to: withEmptyChildren))
        #expect(!base.isEquivalent(to: swapped))
        #expect(!base.isEquivalent(to: annotated))
        let parent = KDLNode(name: "q", children: [base])
        #expect(parent.isEquivalent(to: KDLNode(name: "q", children: [moved])))
        #expect(!parent.isEquivalent(to: KDLNode(name: "q", children: [swapped])))
        #expect(KDLNode.areEquivalent([base, parent], [moved, parent]))
        #expect(!KDLNode.areEquivalent([base], [base, base]))
    }

    @Test("Fehler tragen Text und Ort")
    func errors() {
        let error = KDLParseError(message: "bad", span: .synthetic("x.kdl"))
        #expect(error.span.file == "x.kdl")
        #expect(KDLEditError(message: "no").message == "no")
        let document = KDLDocument(file: "d.kdl", text: "", nodes: [])
        #expect(document.nodes.isEmpty)
    }
}
