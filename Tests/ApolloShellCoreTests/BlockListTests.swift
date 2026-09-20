import Foundation
import Testing
@testable import ApolloShellCore

// Die geteilten Bausteine hinter BarLayout, UtilitiesLayout und
// DashboardLayout: Umsortieren (`Array.move`), Kennungsvergabe/Aufraeumen
// (`BlockList`) und nachsichtiges Listenlesen (`LenientList`). Die
// layout-eigenen Regeln (Vorlagen, Plaetze) bleiben in den jeweiligen
// Testdateien; hier nur die gemeinsame Mechanik, an einem kleinen
// Test-Baustein statt an BarEntry & Co.

private enum FruitKind: String, BlockKind, Codable {
    case apple, pear, custom

    var isUnique: Bool { self != .custom }
}

private struct Fruit: Block, Codable, Equatable {
    var id: String
    var kind: FruitKind

    init(id: String, kind: FruitKind) {
        self.id = id
        self.kind = kind
    }

    init(_ kind: FruitKind, id: String? = nil) {
        self.init(id: id ?? kind.rawValue, kind: kind)
    }
}

@Suite("Array.move: SwiftUI-onMove-Regel, geteilt of BarLayout, UtilitiesLayout, DashboardLayout, PinnedList, Weather")
struct ArrayMoveTests {
    @Test("Ziel zaehlt in der Liste VOR dem Verschieben", arguments: [
        ([0], 2, ["b", "a", "c"]),
        ([2], 0, ["c", "a", "b"]),
        ([0, 2], 1, ["a", "c", "b"]),
        ([1], 1, ["a", "b", "c"]),
    ])
    func moves(source: [Int], destination: Int, expected: [String]) {
        var list = ["a", "b", "c"]
        list.move(fromOffsets: IndexSet(source), toOffset: destination)
        #expect(list == expected)
    }

    @Test("ungueltige oder leere Quelle: nichts passiert")
    func invalidSource() {
        var list = ["a", "b", "c"]
        list.move(fromOffsets: IndexSet([9]), toOffset: 1)
        #expect(list == ["a", "b", "c"])
        list.move(fromOffsets: IndexSet(), toOffset: 1)
        #expect(list == ["a", "b", "c"])
    }
}

@Suite("BlockList: Kennungen, hoechstens-einmal-Arten, Verschieben, nachsichtiges Lesen")
struct BlockListTests {
    @Test("gleiche Art mehrmals: eigene Kennungen, erste ohne Zahl")
    func uniqueIDs() {
        var list = BlockList<Fruit>()
        #expect(list.add(Fruit(.custom)) == "custom")
        #expect(list.add(Fruit(.custom)) == "custom-2")
        #expect(list.add(Fruit(.custom)) == "custom-3")
        #expect(list.entries.map(\.id) == ["custom", "custom-2", "custom-3"])
    }

    @Test("hoechstens-einmal-Art: zweite kommt nicht dazu, die erste bleibt")
    func uniqueKind() {
        var list = BlockList<Fruit>([Fruit(.apple)])
        #expect(list.canAdd(.apple) == false)
        #expect(list.add(Fruit(.apple)) == nil)
        #expect(list.entries.count == 1)
    }

    @Test("beim Einlesen: doppelte hoechstens-einmal-Art weg, leere/doppelte Kennungen neu")
    func normalizedOnInit() {
        let list = BlockList([
            Fruit(id: "", kind: .custom),
            Fruit(id: "x", kind: .apple),
            Fruit(id: "x", kind: .pear),
            Fruit(id: "y", kind: .apple),
        ])
        // Die zweite `apple` (Kennung "y") faellt weg; "custom" ohne Kennung
        // und "pear" mit der schon vergebenen Kennung "x" bekommen neue -
        // "pear" selbst ist noch frei, "pear-2" waere hier nicht noetig.
        #expect(list.entries.map(\.id) == ["custom", "x", "pear"])
        #expect(list.entries.map(\.kind) == [.custom, .apple, .pear])
    }

    @Test("entfernen und andern nur bei gleicher Art")
    func removeAndUpdate() {
        var list = BlockList([Fruit(.apple), Fruit(.pear)])
        list.update(id: "apple", to: Fruit(id: "apple", kind: .pear))
        #expect(list[id: "apple"]?.kind == .apple, "Art muss gleich bleiben, sonst keine Aenderung")
        list.remove(id: "apple")
        #expect(list.entries.map(\.id) == ["pear"])
    }

    @Test("verschieben: fromOffsets/toOffset und an die Stelle eines anderen")
    func moving() {
        var list = BlockList([Fruit(.apple), Fruit(.pear), Fruit(id: "c1", kind: .custom)])
        list.move(fromOffsets: IndexSet([2]), toOffset: 0)
        #expect(list.entries.map(\.id) == ["c1", "apple", "pear"])
        list.move(id: "pear", by: -1)
        #expect(list.entries.map(\.id) == ["c1", "pear", "apple"])
        list.move(id: "apple", onto: "c1")
        #expect(list.entries.map(\.id) == ["apple", "c1", "pear"])
    }

}

@Suite("LenientList: unlesbare Eintraege fallen weg, der Rest bleibt")
struct LenientListTests {
    @Test("Nicht-Objekte und kaputte Eintraege fallen weg")
    func skipsUnreadable() throws {
        let json = #"[{"kind":"clock"},5,null,{"kind":"power"},{"kind":"hologram"}]"#
        let list = try JSONDecoder().decode(LenientList<BarEntry>.self, from: Data(json.utf8))
        #expect(list.values.map(\.kind) == [.clock, .power])
    }

    @Test("gar keine Liste: wirft (BlockList/Layout fangen das per lenient(_:) ab)")
    func failsOnNonArray() {
        let json = #"{"nope": true}"#
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(LenientList<BarEntry>.self, from: Data(json.utf8))
        }
    }
}
