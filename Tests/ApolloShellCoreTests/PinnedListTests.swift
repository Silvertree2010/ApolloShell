import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Nexus: angeheftete Apps bearbeiten")
struct PinnedListTests {
    @Test("Doppelte und leere IDs fallen beim Lesen weg, erste Stelle gewinnt", arguments: [
        (["a", "b", "a", "", "c", "b"], ["a", "b", "c"]),
        ([String](), [String]()),
    ])
    func dedupe(input: [String], expected: [String]) {
        #expect(PinnedList(input).ids == expected)
    }

    @Test("Hinzufuegen: hinten an, nie doppelt, nie leer", arguments: [
        (["a", "b"], "c", true, ["a", "b", "c"]),
        (["a", "b"], "a", false, ["a", "b"]),
        (["a", "b"], "", false, ["a", "b"]),
    ])
    func add(start: [String], id: String, added: Bool, expected: [String]) {
        var list = PinnedList(start)
        let result = list.add(id)
        #expect(result == added)
        #expect(list.ids == expected)
    }

    @Test("volle Liste nimmt nichts mehr", arguments: [PinnedList.limit])
    func fullRejects(limit: Int) {
        var list = PinnedList((0..<limit).map(String.init))
        #expect(list.isFull)
        let result = list.add("neu")
        #expect(!result)
        #expect(list.ids.count == limit)
    }

    @Test("zu lange Datei wird nicht gekuerzt", arguments: [PinnedList.limit + 2])
    func longFileKept(count: Int) {
        let list = PinnedList((0..<count).map(String.init))
        #expect(list.ids.count == count)
        #expect(list.isFull)
    }

    @Test("Entfernen", arguments: [
        (["a", "b", "c"], "b", ["a", "c"]),
        (["a", "b", "c"], "x", ["a", "b", "c"]),
    ])
    func remove(start: [String], id: String, expected: [String]) {
        var list = PinnedList(start)
        list.remove(id)
        #expect(list.ids == expected)
    }

    @Test("Verschieben wie SwiftUIs onMove", arguments: [
        ([0], 2, ["b", "a", "c", "d"]),
        ([3], 0, ["d", "a", "b", "c"]),
        ([0], 4, ["b", "c", "d", "a"]),
        ([1, 2], 4, ["a", "d", "b", "c"]),
        ([2], 2, ["a", "b", "c", "d"]),
        ([2], 3, ["a", "b", "c", "d"]),
        ([9], 0, ["a", "b", "c", "d"]),
    ])
    func moveOffsets(source: [Int], destination: Int, expected: [String]) {
        var list = PinnedList(["a", "b", "c", "d"])
        list.move(fromOffsets: IndexSet(source), toOffset: destination)
        #expect(list.ids == expected)
    }

    @Test("eine Stelle hoch oder runter, am Rand nichts", arguments: [
        ("b", -1, ["b", "a", "c"]),
        ("b", 1, ["a", "c", "b"]),
        ("a", -1, ["a", "b", "c"]),
        ("c", 1, ["a", "b", "c"]),
        ("x", 1, ["a", "b", "c"]),
    ])
    func step(id: String, by: Int, expected: [String]) {
        var list = PinnedList(["a", "b", "c"])
        list.move(id, by: by)
        #expect(list.ids == expected)
    }

    @Test("liest das bisherige Dateiformat", arguments: [
        (#"{ "pinned": ["net.kovidgoyal.kitty", "com.vivaldi.Vivaldi"] }"#, ["net.kovidgoyal.kitty", "com.vivaldi.Vivaldi"]),
        (#"{"pinned":["a","a"],"anderes":1}"#, ["a"]),
        ("kaputt", [String]()),
        (#"{"andere":[]}"#, [String]()),
    ])
    func load(json: String, expected: [String]) {
        #expect(PinnedList.load(from: Data(json.utf8)).ids == expected)
    }

    @Test("schreiben und wieder lesen ergibt dieselbe Reihenfolge", arguments: [
        ["com.apple.systempreferences", "md.obsidian", "net.whatsapp.WhatsApp"],
    ])
    func roundTrip(ids: [String]) {
        let list = PinnedList(ids)
        #expect(PinnedList.load(from: list.encoded()) == list)
        #expect(PinnedList.load(from: nil).ids.isEmpty)
    }
}
