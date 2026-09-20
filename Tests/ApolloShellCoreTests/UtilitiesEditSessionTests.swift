import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Editing: working copy of the control center")
struct UtilitiesEditSessionTests {
    @Test("detect changes; toggle and reorder cards")
    func cards() {
        var s = UtilitiesEditSession(layout: UtilitiesLayout())
        #expect(!s.hasChanges)
        s.setCard(.audio, enabled: false)
        #expect(s.hasChanges)
        #expect(!s.layout.isEnabled(.audio))
        #expect(s.original.isEnabled(.audio))
        s.moveCards(fromOffsets: [0], toOffset: 2)
        #expect(s.layout.cards[0].kind == .audio)
    }

    @Test("unique quick toggle: nil the second time, selected the first time")
    func addUniqueTwice() throws {
        var s = UtilitiesEditSession(layout: UtilitiesLayout(cards: UtilitiesLayout.standardCards, toggles: []))
        let added = s.add(.wifi)
        let id = try #require(added)
        #expect(s.selectedToggleID == id)
        #expect(s.hasChanges)
        s.selectedToggleID = nil
        let second = s.add(.wifi)
        #expect(second == nil)
        #expect(s.selectedToggleID == nil)
    }

    @Test("custom buttons may occur more than once")
    func addCustomTwice() {
        var s = UtilitiesEditSession(layout: UtilitiesLayout(cards: UtilitiesLayout.standardCards, toggles: []))
        let first = s.add(.openApp)
        let second = s.add(.openApp)
        #expect(first != nil)
        #expect(second != nil)
        #expect(s.layout.toggles.count == 2)
    }

    @Test("removing also clears the selection")
    func remove() throws {
        var s = UtilitiesEditSession(layout: UtilitiesLayout(cards: UtilitiesLayout.standardCards, toggles: []))
        let added = s.add(.wifi)
        let id = try #require(added)
        s.remove(toggle: id)
        #expect(!s.layout.contains(.wifi))
        #expect(s.selectedToggleID == nil)
    }

    @Test("change options (kind stays), reorder in the grid")
    func updateAndMove() {
        var s = UtilitiesEditSession(layout: UtilitiesLayout(cards: UtilitiesLayout.standardCards,
                                                              toggles: [.wifi, .bluetooth].map { UtilitiesToggleEntry($0) }))
        s.update(toggle: "wifi", to: .darkMode) // different kind: nothing changed
        #expect(s.layout[toggle: "wifi"]?.kind == .wifi)
        s.update(toggle: "wifi", to: .wifi)
        #expect(s.layout[toggle: "wifi"]?.kind == .wifi)
        s.moveToggle("wifi", onto: "bluetooth")
        #expect(s.layout.toggles.first?.id == "bluetooth")
    }
}
