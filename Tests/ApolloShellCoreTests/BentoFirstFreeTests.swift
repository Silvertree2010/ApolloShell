import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Bento-Geometrie: erste freie Stelle (Galerie-Klick)")
struct BentoFirstFreeTests {
    private func f(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> WidgetFrame {
        WidgetFrame(x: x, y: y, width: w, height: h)
    }

    @Test("Leere Seite: oben links")
    func emptyPage() {
        let frame = BentoGeometry.firstFreeFrame(kind: .clock, others: [])
        #expect(frame == f(0, 0, 110, 130))
    }

    @Test("Mit einer Uhr bei (0,0): rechts daneben")
    func nextToExisting() {
        let others = [f(0, 0, 110, 130)]
        let frame = BentoGeometry.firstFreeFrame(kind: .clock, others: others)
        #expect(frame == f(122, 0, 110, 130))
    }

    @Test("Volle Caelestia-Uebersicht: keine Stelle fuer eine weitere Uhr")
    func fullOverviewPage() {
        let page = DashboardPages.defaultPages(places: .empty, hasBattery: true)[0]
        #expect(page.template == .overview)
        let frame = BentoGeometry.firstFreeFrame(kind: .clock, others: page.frames())
        #expect(frame == nil)
    }
}

@Suite("Bearbeiten: an der ersten freien Stelle hinzufuegen")
struct BentoEditSessionFirstFreeTests {
    @Test("Landet an der ersten freien Stelle und waehlt sich aus")
    func addAtFirstFreeSpot() throws {
        let page = DashboardPage(name: "A", symbol: "star")
        let pages = try #require(DashboardPages(pages: [page]))
        var s = BentoEditSession(pages: pages, pageID: page.id)
        let addedID = s.addAtFirstFreeSpot(.clock)
        let id = try #require(addedID)
        #expect(s.page.widgets.first?.id == id)
        #expect(s.page.widgets.first?.frame == WidgetFrame(x: 0, y: 0, width: 110, height: 130))
        #expect(s.selectedWidgetID == id)
    }

    @Test("Volle Seite: nil, nichts geaendert")
    func noSpace() throws {
        let full = DashboardPages.defaultPages(places: .empty, hasBattery: true)[0]
        let pages = try #require(DashboardPages(pages: [full]))
        var s = BentoEditSession(pages: pages, pageID: full.id)
        let id = s.addAtFirstFreeSpot(.clock)
        #expect(id == nil)
        #expect(s.page.widgets.count == full.widgets.count)
    }
}
