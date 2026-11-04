import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Editing: the working copy, the preview while dragging, cancel")
struct BentoEditSessionTests {
    private func f(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> WidgetFrame {
        WidgetFrame(x: x, y: y, width: w, height: h)
    }

    private func session() throws -> (BentoEditSession, WidgetInstance.ID) {
        let clock = WidgetInstance(kind: .clock, frame: f(0, 0, 110, 130))
        let page = DashboardPage(name: "A", symbol: "star", widgets: [clock])
        let pages = try #require(DashboardPages(pages: [page]))
        return (BentoEditSession(pages: pages, pageID: page.id), clock.id)
    }

    @Test("Dragging: the preview snaps and says whether it fits; only the drop changes anything")
    func move() throws {
        var (s, id) = try session()
        let ok = s.previewMove(id, proposed: f(4, 146, 110, 130))
        #expect(ok.frame == f(0, 146, 110, 130))   // x snaps to the edge, y has no target
        #expect(ok.valid)
        #expect(s.page.widgets[0].frame == f(0, 0, 110, 130))
        let committed = s.commit(id, frame: ok.frame)
        #expect(committed)
        #expect(s.page.widgets[0].frame == ok.frame)
        let outside = s.previewMove(id, proposed: f(800, 0, 110, 130))
        #expect(!outside.valid)
        let committedOutside = s.commit(id, frame: outside.frame)
        #expect(!committedOutside)
    }

    @Test("Size: the preview follows the sizes of the kind")
    func resize() throws {
        let (s, id) = try session()
        let r = s.previewResize(id, proposedWidth: 300, proposedHeight: 240)
        #expect(r.frame == f(0, 0, 300, 250))
        #expect(r.valid)
    }

    @Test("Dropping out of Nexus: the smallest size, invalid when too close")
    func drop() throws {
        var (s, _) = try session()
        let near = s.previewDrop(.clock, x: 60, y: 60)
        #expect(!near.valid)
        let free = s.previewDrop(.clock, x: 300, y: 300)
        #expect(free.valid)
        let addedID = s.add(.clock, frame: free.frame)
        let added = try #require(addedID)
        #expect(s.page.widgets.count == 2)
        #expect(s.selectedWidgetID == added)
    }

    @Test("Removing, the options, the selection goes with the widget")
    func removeAndOptions() throws {
        var (s, id) = try session()
        s.selectedWidgetID = id
        s.setOptions(WidgetOptions(clock: DashboardClockOptions(timeZone: "Asia/Tokyo")), for: id)
        #expect(s.page.widgets[0].options.clock?.timeZone == "Asia/Tokyo")
        s.remove(id)
        #expect(s.page.widgets.isEmpty)
        #expect(s.selectedWidgetID == nil)
    }

    @Test("The minus finds its widget even after a page switch")
    func removeAfterPageSwitch() throws {
        var (s, id) = try session()
        // The minus badge lets the widget fade out for 0.18 s and only then
        // removes it. Whoever switches pages in that moment used to lose
        // the removal: it went to the page shown by then.
        var pages = s.pages
        let other = pages.addPage(name: "B")
        s = BentoEditSession(pages: pages, pageID: s.pageID)
        s.pageID = other
        s.remove(id)
        #expect(s.pages.pages[0].widgets.isEmpty)
        #expect(s.hasChanges)
    }

    @Test("Recognising changes; switching the page deselects")
    func changes() throws {
        var (s, id) = try session()
        #expect(!s.hasChanges)
        s.selectedWidgetID = id
        s.remove(id)
        #expect(s.hasChanges)
        #expect(s.original.pages[0].widgets.count == 1)
        let other = DashboardPage(name: "B", symbol: "star")
        var pages = s.pages
        pages.update(other) // unbekannt: nichts
        #expect(pages == s.pages)
    }
}
