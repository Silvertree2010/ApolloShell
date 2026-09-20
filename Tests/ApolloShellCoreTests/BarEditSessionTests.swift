import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Editing: working copy of the sidebar")
struct BarEditSessionTests {
    /// The Caelestia bar, the same default the shell starts with.
    private var standard: BarLayout { BarPreset.caelestia.layout }

    @Test("A fresh session has no changes and nothing selected")
    func fresh() {
        let s = BarEditSession(layout: standard)
        #expect(!s.hasChanges)
        #expect(s.selectedEntryID == nil)
        #expect(s.layout == s.original)
    }

    @Test("Adding a block selects it and counts as a change")
    func add() throws {
        var s = BarEditSession(layout: BarLayout([BarEntry(.clock)]))
        let added = s.add(.appButton)
        let id = try #require(added)
        #expect(s.selectedEntryID == id)
        #expect(s.hasChanges)
        #expect(s.layout.entries.map(\.kind).contains(.appButton))
        #expect(s.original.entries.map(\.kind) == [.clock])
    }

    @Test("A kind that may exist only once is refused, and nothing changes")
    func addUniqueTwice() {
        var s = BarEditSession(layout: BarLayout([BarEntry(.dock)]))
        let second = s.add(.dock)
        #expect(second == nil)
        #expect(s.selectedEntryID == nil)
        #expect(!s.hasChanges)
    }

    @Test("The same kind may come twice when the layout allows it")
    func addTwice() {
        var s = BarEditSession(layout: BarLayout([]))
        let first = s.add(.appButton)
        let second = s.add(.appButton)
        #expect(first != nil)
        #expect(second != nil)
        #expect(first != second)
        #expect(s.layout.entries.count == 2)
    }

    @Test("Adding at a place puts the block exactly there")
    func addAtIndex() throws {
        var s = BarEditSession(layout: BarLayout([BarEntry(.clock), BarEntry(.power)]))
        let inserted = s.add(.spacer, at: 1)
        let id = try #require(inserted)
        #expect(s.layout.entries.map(\.id)[1] == id)
    }

    @Test("Removing the selected block clears the selection")
    func removeSelected() throws {
        var s = BarEditSession(layout: standard)
        let id = try #require(s.layout.entries.first?.id)
        s.selectedEntryID = id
        s.remove(id: id)
        #expect(s.selectedEntryID == nil)
        #expect(s.layout[id: id] == nil)
        #expect(s.hasChanges)
    }

    @Test("Removing another block leaves the selection alone")
    func removeOther() throws {
        var s = BarEditSession(layout: standard)
        let ids = s.layout.entries.map(\.id)
        try #require(ids.count >= 2)
        s.selectedEntryID = ids[0]
        s.remove(id: ids[1])
        #expect(s.selectedEntryID == ids[0])
    }

    @Test("Options change, the kind stays")
    func update() throws {
        var s = BarEditSession(layout: BarLayout([BarEntry(.clock)]))
        let id = try #require(s.layout.entries.first?.id)
        s.update(id: id, to: .clock(BarClockOptions(showIcon: false)))
        #expect(s.layout[id: id]?.kind == .clock)
        #expect(s.hasChanges)
        guard case let .clock(edited) = try #require(s.layout[id: id]).module,
              case let .clock(before) = try #require(s.original[id: id]).module else {
            Issue.record("the clock stays a clock")
            return
        }
        #expect(!edited.showIcon)
        #expect(before.showIcon)
    }

    @Test("Moving works both ways and matches the layout on its own")
    func move() {
        let start = BarLayout([BarEntry(.dashboardButton), BarEntry(.clock), BarEntry(.power)])
        var s = BarEditSession(layout: start)
        var plain = start

        s.move(fromOffsets: [0], toOffset: 2)
        plain.move(fromOffsets: [0], toOffset: 2)
        #expect(s.layout.entries.map(\.kind) == plain.entries.map(\.kind))

        let id = s.layout.entries[0].id
        s.move(id: id, by: 1)
        plain.move(id: id, by: 1)
        #expect(s.layout.entries.map(\.kind) == plain.entries.map(\.kind))
    }

    @Test("Dragging one block onto another takes its place")
    func moveOnto() {
        let start = BarLayout([BarEntry(.dashboardButton), BarEntry(.clock), BarEntry(.power)])
        var s = BarEditSession(layout: start)
        var plain = start
        let ids = s.layout.entries.map(\.id)

        s.move(id: ids[2], onto: ids[0])
        plain.move(id: ids[2], onto: ids[0])
        #expect(s.layout.entries.map(\.id) == plain.entries.map(\.id))
        #expect(s.layout.entries[0].kind == .power)
        #expect(s.hasChanges)
    }

    @Test("Moving a block back and forth is no change at all")
    func moveBackIsNoChange() {
        var s = BarEditSession(layout: standard)
        let id = s.layout.entries[0].id
        s.move(id: id, by: 1)
        #expect(s.hasChanges)
        s.move(id: id, by: -1)
        #expect(!s.hasChanges)
    }
}
