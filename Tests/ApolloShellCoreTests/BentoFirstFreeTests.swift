import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Bento geometry: the first free place (a gallery click)")
struct BentoFirstFreeTests {
    private func f(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> WidgetFrame {
        WidgetFrame(x: x, y: y, width: w, height: h)
    }

    @Test("An empty page: at the top left")
    func emptyPage() {
        let frame = BentoGeometry.firstFreeFrame(kind: .clock, others: [])
        #expect(frame == f(0, 0, 110, 130))
    }

    @Test("With a clock at (0,0): to the right of it")
    func nextToExisting() {
        let others = [f(0, 0, 110, 130)]
        let frame = BentoGeometry.firstFreeFrame(kind: .clock, others: others)
        #expect(frame == f(122, 0, 110, 130))
    }

    @Test("A full Caelestia overview: no place for another clock")
    func fullOverviewPage() {
        let page = DashboardPages.defaultPages(places: .empty, hasBattery: true)[0]
        #expect(page.template == .overview)
        let frame = BentoGeometry.firstFreeFrame(kind: .clock, others: page.frames())
        #expect(frame == nil)
    }
}

@Suite("Editing: adding at the first free place")
struct BentoEditSessionFirstFreeTests {
    @Test("It lands at the first free place and selects itself")
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

    @Test("A full page: nil, nothing changed")
    func noSpace() throws {
        let full = DashboardPages.defaultPages(places: .empty, hasBattery: true)[0]
        let pages = try #require(DashboardPages(pages: [full]))
        var s = BentoEditSession(pages: pages, pageID: full.id)
        let id = s.addAtFirstFreeSpot(.clock)
        #expect(id == nil)
        #expect(s.page.widgets.count == full.widgets.count)
    }
}
