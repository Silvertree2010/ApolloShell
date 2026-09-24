import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Editing: the sidebar and the menu bar together")
struct BarsEditSessionTests {
    private let topStart = BarPlace.menuBar(.start)
    private let topCenter = BarPlace.menuBar(.center)
    private let topEnd = BarPlace.menuBar(.end)

    /// Sidebar: dock and clock. Menu bar: spaces | clock + weather (joined) | status.
    private func session() -> BarEditSession {
        let menuBar = ApolloMenuBar(enabled: true,
                                    start: BarLayout([BarEntry(.workspaces)]),
                                    center: BarLayout([BarEntry(.clock), BarEntry(.weather).joined()]),
                                    end: BarLayout([BarEntry(.statusIcons)]))
        return BarEditSession(layout: BarLayout([BarEntry(.dock), BarEntry(.clock)]), menuBar: menuBar)
    }

    @Test("A fresh session over both has no changes")
    func fresh() {
        let s = session()
        #expect(!s.hasChanges)
        #expect(s.selection == nil)
        #expect(s[topCenter].entries.map(\.kind) == [.clock, .weather])
    }

    @Test("Adding into a zone selects the new block there; the sidebar stays")
    func addToZone() throws {
        var s = session()
        let r1 = s.add(.battery, to: topEnd, at: 0)
        let id = try #require(r1)
        #expect(s.selection == BarEntryRef(place: topEnd, id: id))
        #expect(s.selectedEntryID == nil)
        #expect(s[topEnd].entries.map(\.kind) == [.battery, .statusIcons])
        #expect(s.layout == s.original)
        #expect(s.hasChanges)
    }

    @Test("Dock and status icons are unique per bar, not per zone")
    func uniquePerBar() {
        var s = session()
        #expect(s.add(.statusIcons, to: topStart) == nil)
        #expect(!s.canAdd(.statusIcons, to: topCenter))
        // The sidebar is its own bar: its status icons do not block the top.
        #expect(s.canAdd(.dock, to: topStart))
        #expect(!s.canAdd(.dock, to: .sidebar))
        #expect(!s.hasChanges)
    }

    @Test("Moving within a zone, across zones and across bars")
    func moveEverywhere() throws {
        var s = session()
        let weather = BarEntryRef(place: topCenter, id: "weather")
        // Within the zone: to the front.
        let r2 = s.move(weather, to: topCenter, at: 0)
        let front = try #require(r2)
        #expect(s[topCenter].entries.map(\.kind) == [.weather, .clock])
        // Across zones.
        let r3 = s.move(front, to: topStart, at: 1)
        let inStart = try #require(r3)
        #expect(s[topStart].entries.map(\.kind) == [.workspaces, .weather])
        #expect(s[topCenter].entries.map(\.kind) == [.clock])
        // Across bars, into the sidebar and out again.
        let r4 = s.move(inStart, to: .sidebar, at: 0)
        let inSidebar = try #require(r4)
        #expect(inSidebar.place == .sidebar)
        #expect(s.layout.entries.map(\.kind) == [.weather, .dock, .clock])
        #expect(s[topStart].entries.map(\.kind) == [.workspaces])
        #expect(s.move(inSidebar, to: topEnd, at: 5) != nil)
        #expect(s[topEnd].entries.map(\.kind) == [.statusIcons, .weather])
    }

    @Test("An id the target already uses gets a fresh one, and the selection follows")
    func idCollision() throws {
        var s = session()
        let clock = BarEntryRef(place: topCenter, id: "clock")
        s.selection = clock
        s.update(clock, to: .clock(BarClockOptions(showIcon: false)))
        let r5 = s.move(clock, to: .sidebar, at: 0)
        let moved = try #require(r5)
        #expect(moved.id != "clock")
        #expect(Set(s.layout.entries.map(\.id)).count == 3)
        #expect(s.selection == moved)
        // Options travel along.
        #expect(s.entry(moved)?.module == .clock(BarClockOptions(showIcon: false)))
    }

    @Test("A free id is kept when moving")
    func keepsFreeID() throws {
        var s = session()
        let r6 = s.move(BarEntryRef(place: topCenter, id: "weather"), to: topStart, at: 0)
        let moved = try #require(r6)
        #expect(moved.id == "weather")
    }

    @Test("A second Dock cannot be dragged into a bar that has one; within a bar it moves freely")
    func moveRespectsUniqueness() throws {
        var s = session()
        let r7 = s.add(.dock, to: topStart)
        _ = try #require(r7)
        let before = s
        #expect(s.move(.sidebar("dock"), to: topEnd, at: 0) == nil)
        #expect(s == before)
        // Between zones of the same bar the one Dock may travel.
        #expect(s.move(BarEntryRef(place: topStart, id: "dock"), to: topEnd, at: 0) != nil)
        #expect(s[topEnd].entries.first?.kind == .dock)
    }

    @Test("Dragging onto a block: its own list takes the spot, another list goes before it")
    func moveOnto() throws {
        var s = session()
        let result = s.move(BarEntryRef(place: topStart, id: "workspaces"),
                            onto: BarEntryRef(place: topCenter, id: "clock"))
        let moved = try #require(result)
        #expect(moved.place == topCenter)
        #expect(s[topCenter].entries.map(\.kind) == [.workspaces, .clock, .weather])
        // Two sidebar blocks move exactly as `move(id:onto:)` does.
        var plain = s.layout
        s.move(.sidebar("clock"), onto: .sidebar("dock"))
        plain.move(id: "clock", onto: "dock")
        #expect(s.layout == plain)
    }

    @Test("Removing: selection cleared, the group left behind stays whole")
    func removeKeepsGroup() {
        var s = session()
        let clock = BarEntryRef(place: topCenter, id: "clock")
        s.selection = clock
        s.remove(clock)
        #expect(s.selection == nil)
        #expect(s[topCenter].entries.map(\.kind) == [.weather])
        #expect(s[topCenter].entries[0].joinsPrevious == false)
    }

    @Test("A block leaving the head of a group hands it on instead of merging groups")
    func leavingHead() throws {
        var s = session()
        let r8 = s.add(.battery, to: topCenter, at: 0)
        _ = try #require(r8)
        // battery | clock + weather: move the clock away.
        s.move(BarEntryRef(place: topCenter, id: "clock"), to: topStart, at: 0)
        let groups = ApolloMenuBar.groups(of: s[topCenter]).map { $0.map(\.kind) }
        #expect(groups == [[.battery], [.weather]])
    }

    @Test("A block landing inside a group joins it; at a group's edge it stays alone")
    func landingJoins() throws {
        var s = session()
        s.move(BarEntryRef(place: topStart, id: "workspaces"), to: topCenter, at: 1)
        #expect(ApolloMenuBar.groups(of: s[topCenter]).map { $0.map(\.kind) } == [[.clock, .workspaces, .weather]])
        s.move(BarEntryRef(place: topCenter, id: "workspaces"), to: topCenter, at: 3)
        #expect(ApolloMenuBar.groups(of: s[topCenter]).map { $0.map(\.kind) } == [[.clock, .weather], [.workspaces]])
    }

    @Test("Dropped where it stands, a joined block keeps its group")
    func moveInPlace() throws {
        var s = session()
        let weather = BarEntryRef(place: topCenter, id: "weather")
        #expect(s.moveToEnd(weather, of: topCenter) == weather)
        #expect(!s.hasChanges)
    }

    @Test("Join with previous: toggles, keeps through option changes, never for the first block or the sidebar")
    func join() {
        var s = session()
        let weather = BarEntryRef(place: topCenter, id: "weather")
        s.toggleJoin(weather)
        #expect(s.entry(weather)?.joinsPrevious == false)
        s.toggleJoin(weather)
        #expect(s.entry(weather)?.joinsPrevious == true)
        s.update(weather, to: .weather(BarWeatherOptions(showTemperature: false)))
        #expect(s.entry(weather)?.joinsPrevious == true)
        let clock = BarEntryRef(place: topCenter, id: "clock")
        #expect(!s.canJoin(clock))
        s.toggleJoin(clock)
        #expect(s.entry(clock)?.joinsPrevious == false)
        #expect(!s.canJoin(.sidebar("clock")))
        s.toggleJoin(.sidebar("clock"))
        #expect(s.layout == s.original)
    }

    @Test("Changes and back again count as none")
    func hasChangesRoundTrip() throws {
        var s = session()
        let r9 = s.move(BarEntryRef(place: topStart, id: "workspaces"), to: topEnd, at: 0)
        let moved = try #require(r9)
        #expect(s.hasChanges)
        s.move(moved, to: topStart, at: 0)
        #expect(!s.hasChanges)
    }

    @Test("The sidebar selection alone is still `selectedEntryID`")
    func sidebarSelection() {
        var s = session()
        s.selectedEntryID = "clock"
        #expect(s.selection == .sidebar("clock"))
        s.selection = BarEntryRef(place: topCenter, id: "clock")
        #expect(s.selectedEntryID == nil)
        s.selectedEntryID = nil
        #expect(s.selection == nil)
    }

    @Test("Drag payloads: sidebar ids unchanged, menu bar ids carry their zone")
    func payload() {
        #expect(BarEntryRef.sidebar("clock-2").payload == "clock-2")
        let ref = BarEntryRef(place: .menuBar(.end), id: "clock")
        #expect(ref.payload == "menuBar.end/clock")
        #expect(BarEntryRef(payload: ref.payload) == ref)
        #expect(BarEntryRef(payload: "clock-2") == .sidebar("clock-2"))
        #expect(BarEntryRef(payload: "odd/id") == .sidebar("odd/id"))
    }
}
