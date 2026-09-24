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

    static let rich = """
    panel "bar" {
        button id="go" {
            on-click { toggle "calendar" }
        }
        text "{battery.percent}" id="level"
        each app in="{apps.running}" key="{app.bundle-id}" {
            text "{app.name}"
        }
        when "{battery.present}" {
            text "on battery"
        }
    }
    popup "calendar" {
        text "C"
    }
    """

    @Test("Aenderung an Handler, Binding, Art, each und when markiert nur die betroffene Oberflaeche", arguments: [
        ("toggle \"calendar\"", "toggle \"bar\""),
        ("on-click {", "on-click debounce=\"200ms\" {"),
        ("text \"{battery.percent}\"", "text \"{battery.percent | percent}\""),
        ("text \"{battery.percent}\" id=\"level\"", "icon \"{battery.percent}\" id=\"level\""),
        ("key=\"{app.bundle-id}\"", "key=\"{app.name}\""),
        ("text \"{app.name}\"", "text \"{app.title}\""),
        ("when \"{battery.present}\"", "when \"{!battery.present}\""),
        ("text \"on battery\"", "text \"on power\""),
    ])
    func detailChanges(_ replacement: (String, String)) {
        #expect(Self.rich.contains(replacement.0))
        let new = Self.rich.replacingOccurrences(of: replacement.0, with: replacement.1)
        let old = IRHarness.clean(Self.rich)
        let changed = IRHarness.clean(new)
        let change = IRDiff.surfaces(old: old, new: changed)
        #expect(change.changed.map(\.id) == ["bar"])
        #expect(change.added.isEmpty && change.removed.isEmpty)
        #expect(change.unchanged == ["calendar"])
    }

    @Test("verschobene Zeilen allein aendern weder Handler noch Aktionen noch Bindings")
    func shiftedSourceIsUnchanged() {
        let old = IRHarness.clean(Self.rich)
        let shifted = IRHarness.clean("\n\n" + Self.rich.replacingOccurrences(of: "    ", with: "  "))
        #expect(old != shifted)
        #expect(IRDiff.surfaces(old: old, new: shifted) == SurfaceChange(unchanged: ["bar", "calendar"]))
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
