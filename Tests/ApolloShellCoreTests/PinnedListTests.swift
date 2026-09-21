import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Nexus: editing pinned apps")
struct PinnedListTests {
    @Test("Duplicate and empty IDs are dropped when reading, first spot wins", arguments: [
        (["a", "b", "a", "", "c", "b"], ["a", "b", "c"]),
        ([String](), [String]()),
    ])
    func dedupe(input: [String], expected: [String]) {
        #expect(PinnedList(input).ids == expected)
    }

    @Test("Adding: appended at the end, never duplicated, never empty", arguments: [
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

    @Test("a full list takes nothing more", arguments: [PinnedList.limit])
    func fullRejects(limit: Int) {
        var list = PinnedList((0..<limit).map(String.init))
        #expect(list.isFull)
        let result = list.add("new")
        #expect(!result)
        #expect(list.ids.count == limit)
    }

    @Test("an overlong file is not truncated", arguments: [PinnedList.limit + 2])
    func longFileKept(count: Int) {
        let list = PinnedList((0..<count).map(String.init))
        #expect(list.ids.count == count)
        #expect(list.isFull)
    }

    @Test("Removing", arguments: [
        (["a", "b", "c"], "b", ["a", "c"]),
        (["a", "b", "c"], "x", ["a", "b", "c"]),
    ])
    func remove(start: [String], id: String, expected: [String]) {
        var list = PinnedList(start)
        list.remove(id)
        #expect(list.ids == expected)
    }

    @Test("Moving like SwiftUI's onMove", arguments: [
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

    @Test("dropped onto another pin, it takes that place", arguments: [
        ("a", "c", ["b", "c", "a", "d"]),
        ("d", "b", ["a", "d", "b", "c"]),
        ("b", "a", ["b", "a", "c", "d"]),
        ("b", "b", ["a", "b", "c", "d"]),
        ("x", "b", ["a", "b", "c", "d"]),
        ("b", "x", ["a", "b", "c", "d"]),
    ])
    func dropOnto(id: String, target: String, expected: [String]) {
        var list = PinnedList(["a", "b", "c", "d"])
        list.move(id, onto: target)
        #expect(list.ids == expected)
    }

    @Test("one step up or down, nothing at the edge", arguments: [
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

    @Test("reads the previous file format", arguments: [
        (#"{ "pinned": ["net.kovidgoyal.kitty", "com.vivaldi.Vivaldi"] }"#, ["net.kovidgoyal.kitty", "com.vivaldi.Vivaldi"]),
        (#"{"pinned":["a","a"],"anderes":1}"#, ["a"]),
        ("broken", [String]()),
        (#"{"andere":[]}"#, [String]()),
    ])
    func load(json: String, expected: [String]) {
        #expect(PinnedList.load(from: Data(json.utf8)).ids == expected)
    }

    @Test("writing and reading again yields the same order", arguments: [
        ["com.apple.systempreferences", "md.obsidian", "net.whatsapp.WhatsApp"],
    ])
    func roundTrip(ids: [String]) {
        let list = PinnedList(ids)
        #expect(PinnedList.load(from: list.encoded()) == list)
        #expect(PinnedList.load(from: nil).ids.isEmpty)
    }

    /// Nexus writes the whole list after every pin. If it reads a
    /// broken file as empty, the old pins would be gone afterwards - so
    /// "broken" must be distinguishable from "missing" and "empty".
    @Test("unreadable: only an existing, broken file", arguments: [
        ("broken", true),
        (#"{ "pinned": ["a", "b" }"#, true),
        (#"{"andere":[]}"#, true),
        ("", true),
        (#"{ "pinned": ["a"] }"#, false),
        (#"{ "pinned": [] }"#, false),
        (#"{"pinned":["a"],"anderes":1}"#, false),
    ])
    func unreadable(json: String, expected: Bool) {
        #expect(PinnedList.isUnreadable(Data(json.utf8)) == expected)
    }

    @Test("missing file is not unreadable")
    func missingIsNotUnreadable() {
        #expect(!PinnedList.isUnreadable(nil))
    }
}
