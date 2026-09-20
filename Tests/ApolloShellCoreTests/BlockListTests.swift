import Foundation
import Testing
@testable import ApolloShellCore

// The shared building blocks behind BarLayout, UtilitiesLayout and
// DashboardLayout: Umsortieren (`Array.move`), Kennungsvergabe/Aufraeumen
// (`BlockList`) and lenient list reading (`LenientList`). The rules of a
// layout's own (templates, places) stay in their own test files; only the
// shared mechanics are here, on a small
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

@Suite("Array.move: the SwiftUI onMove rule, shared by BarLayout, UtilitiesLayout, DashboardLayout, PinnedList, Weather")
struct ArrayMoveTests {
    @Test("The target counts in the list BEFORE the move", arguments: [
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

    @Test("an invalid or empty source: nothing happens")
    func invalidSource() {
        var list = ["a", "b", "c"]
        list.move(fromOffsets: IndexSet([9]), toOffset: 1)
        #expect(list == ["a", "b", "c"])
        list.move(fromOffsets: IndexSet(), toOffset: 1)
        #expect(list == ["a", "b", "c"])
    }
}

@Suite("BlockList: ids, at-most-once kinds, moving, lenient reading")
struct BlockListTests {
    @Test("the same kind several times: ids of their own, the first without a number")
    func uniqueIDs() {
        var list = BlockList<Fruit>()
        #expect(list.add(Fruit(.custom)) == "custom")
        #expect(list.add(Fruit(.custom)) == "custom-2")
        #expect(list.add(Fruit(.custom)) == "custom-3")
        #expect(list.entries.map(\.id) == ["custom", "custom-2", "custom-3"])
    }

    @Test("an at-most-once kind: the second does not come in, the first stays")
    func uniqueKind() {
        var list = BlockList<Fruit>([Fruit(.apple)])
        #expect(list.canAdd(.apple) == false)
        #expect(list.add(Fruit(.apple)) == nil)
        #expect(list.entries.count == 1)
    }

    @Test("when reading: a duplicate at-most-once kind goes, empty/duplicate ids become new")
    func normalizedOnInit() {
        let list = BlockList([
            Fruit(id: "", kind: .custom),
            Fruit(id: "x", kind: .apple),
            Fruit(id: "x", kind: .pear),
            Fruit(id: "y", kind: .apple),
        ])
        // The second `apple` (the id "y") falls away; "custom" without an id
        // and "pear" with the id "x" that is taken already get new ones -
        // "pear" itself is still free, and "pear-2" would not be needed here.
        #expect(list.entries.map(\.id) == ["custom", "x", "pear"])
        #expect(list.entries.map(\.kind) == [.custom, .apple, .pear])
    }

    @Test("removing and changing only with the same kind")
    func removeAndUpdate() {
        var list = BlockList([Fruit(.apple), Fruit(.pear)])
        list.update(id: "apple", to: Fruit(id: "apple", kind: .pear))
        #expect(list[id: "apple"]?.kind == .apple, "the kind has to stay the same, otherwise no change")
        list.remove(id: "apple")
        #expect(list.entries.map(\.id) == ["pear"])
    }

    @Test("moving: fromOffsets/toOffset and to the place of another one")
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

@Suite("LenientList: unreadable entries fall away, the rest stays")
struct LenientListTests {
    @Test("Non-objects and broken entries fall away")
    func skipsUnreadable() throws {
        let json = #"[{"kind":"clock"},5,null,{"kind":"power"},{"kind":"hologram"}]"#
        let list = try JSONDecoder().decode(LenientList<BarEntry>.self, from: Data(json.utf8))
        #expect(list.values.map(\.kind) == [.clock, .power])
    }

    @Test("no list at all: it throws (BlockList/Layout catch that through lenient(_:))")
    func failsOnNonArray() {
        let json = #"{"nope": true}"#
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(LenientList<BarEntry>.self, from: Data(json.utf8))
        }
    }
}
