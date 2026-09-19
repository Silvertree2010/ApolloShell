import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Bearbeiten: Arbeitskopie des Kontrollzentrums")
struct UtilitiesEditSessionTests {
    @Test("Aenderungen erkennen; Karten schalten und umsortieren")
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

    @Test("Einzigartiger Schnellschalter: zweites Mal nil, waehlt beim ersten Mal aus")
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

    @Test("Eigene Knoepfe duerfen mehrfach vorkommen")
    func addCustomTwice() {
        var s = UtilitiesEditSession(layout: UtilitiesLayout(cards: UtilitiesLayout.standardCards, toggles: []))
        let first = s.add(.openApp)
        let second = s.add(.openApp)
        #expect(first != nil)
        #expect(second != nil)
        #expect(s.layout.toggles.count == 2)
    }

    @Test("Entfernen loescht auch die Auswahl")
    func remove() throws {
        var s = UtilitiesEditSession(layout: UtilitiesLayout(cards: UtilitiesLayout.standardCards, toggles: []))
        let added = s.add(.wifi)
        let id = try #require(added)
        s.remove(toggle: id)
        #expect(!s.layout.contains(.wifi))
        #expect(s.selectedToggleID == nil)
    }

    @Test("Optionen aendern (Art bleibt), im Raster umsortieren")
    func updateAndMove() {
        var s = UtilitiesEditSession(layout: UtilitiesLayout(cards: UtilitiesLayout.standardCards,
                                                              toggles: [.wifi, .bluetooth].map { UtilitiesToggleEntry($0) }))
        s.update(toggle: "wifi", to: .darkMode) // andere Art: nichts geaendert
        #expect(s.layout[toggle: "wifi"]?.kind == .wifi)
        s.update(toggle: "wifi", to: .wifi)
        #expect(s.layout[toggle: "wifi"]?.kind == .wifi)
        s.moveToggle("wifi", onto: "bluetooth")
        #expect(s.layout.toggles.first?.id == "bluetooth")
    }
}
