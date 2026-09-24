import Testing
import Foundation
import ApolloBase
@testable import ApolloConfig

@Suite("IRDiff der Oberflaechen")
struct IRDiffTests {
    static let base = """
    panel "bar" {
        text "A" id="a"
        text "B" id="b"
    }
    popup "calendar" {
        text "C"
    }
    """

    static func diff(_ old: String, _ new: String) -> SurfaceChange {
        IRDiff.surfaces(old: IRHarness.build(old).ir, new: IRHarness.build(new).ir)
    }

    @Test("gleiche Config ergibt nur unveraenderte Oberflaechen")
    func identical() {
        let change = Self.diff(Self.base, Self.base)
        #expect(change == SurfaceChange(unchanged: ["bar", "calendar"]))
    }

    @Test("Oberflaeche neu und weg")
    func surfaceAddedAndRemoved() {
        let change = Self.diff(Self.base, """
        panel "bar" {
            text "A" id="a"
            text "B" id="b"
        }
        osd "volume" {
            text "V"
        }
        """)
        #expect(change.added.map(\.id) == ["volume"])
        #expect(change.removed == ["calendar"])
        #expect(change.changed.isEmpty)
        #expect(change.unchanged == ["bar"])
    }

    @Test("Element geaendert, verschoben, neu und weg markiert die Oberflaeche als geaendert", arguments: [
        "panel \"bar\" {\n    text \"A2\" id=\"a\"\n    text \"B\" id=\"b\"\n}\npopup \"calendar\" {\n    text \"C\"\n}",
        "panel \"bar\" {\n    text \"B\" id=\"b\"\n    text \"A\" id=\"a\"\n}\npopup \"calendar\" {\n    text \"C\"\n}",
        "panel \"bar\" {\n    text \"A\" id=\"a\"\n    text \"B\" id=\"b\"\n    text \"N\"\n}\npopup \"calendar\" {\n    text \"C\"\n}",
        "panel \"bar\" {\n    text \"A\" id=\"a\"\n}\npopup \"calendar\" {\n    text \"C\"\n}",
        "panel \"bar\" anchor=\"top\" {\n    text \"A\" id=\"a\"\n    text \"B\" id=\"b\"\n}\npopup \"calendar\" {\n    text \"C\"\n}",
    ])
    func elementChanges(_ new: String) {
        let change = Self.diff(Self.base, new)
        #expect(change.changed.map(\.id) == ["bar"])
        #expect(change.added.isEmpty && change.removed.isEmpty)
        #expect(change.unchanged == ["calendar"])
    }

    @Test("Art gewechselt bei gleicher Kennung ist eine Aenderung, kein Entfernen")
    func kindChanged() {
        let change = Self.diff(Self.base, """
        panel "bar" {
            text "A" id="a"
            text "B" id="b"
        }
        overlay "calendar" {
            text "C"
        }
        """)
        #expect(change.changed.map(\.kind) == ["overlay"])
        #expect(change.removed.isEmpty && change.added.isEmpty)
    }

    @Test("Reihenfolge folgt der neuen Config, verschobene Quellorte allein sind keine Aenderung")
    func ordering() {
        let old = IRHarness.build("panel \"a\" { }\npanel \"b\" { }\npanel \"c\" { }").ir
        let new = IRHarness.build("panel \"d\" { }\npanel \"c\" { }\npanel \"e\" { }\npanel \"a\" { }").ir
        let change = IRDiff.surfaces(old: old, new: new)
        #expect(change.added.map(\.id) == ["d", "e"])
        #expect(change.removed == ["b"])
        #expect(change.changed.isEmpty)
        #expect(change.unchanged == ["c", "a"])
    }
}
