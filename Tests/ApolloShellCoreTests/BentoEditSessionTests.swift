import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Bearbeiten: Arbeitskopie, Vorschau beim Ziehen, Abbrechen")
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

    @Test("Ziehen: Vorschau rastet ein und sagt, ob es passt; erst Loslassen aendert")
    func move() throws {
        var (s, id) = try session()
        let ok = s.previewMove(id, proposed: f(4, 146, 110, 130))
        #expect(ok.frame == f(0, 146, 110, 130))   // x rastet am Rand ein, y hat kein Ziel
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

    @Test("Groesse: Vorschau nach den Groessen der Art")
    func resize() throws {
        let (s, id) = try session()
        let r = s.previewResize(id, proposedWidth: 300, proposedHeight: 240)
        #expect(r.frame == f(0, 0, 300, 250))
        #expect(r.valid)
    }

    @Test("Ablegen aus Nexus: kleinste Groesse, ungueltig wenn zu nah")
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

    @Test("Entfernen, Optionen, Auswahl faellt mit dem Widget")
    func removeAndOptions() throws {
        var (s, id) = try session()
        s.selectedWidgetID = id
        s.setOptions(WidgetOptions(clock: DashboardClockOptions(timeZone: "Asia/Tokyo")), for: id)
        #expect(s.page.widgets[0].options.clock?.timeZone == "Asia/Tokyo")
        s.remove(id)
        #expect(s.page.widgets.isEmpty)
        #expect(s.selectedWidgetID == nil)
    }

    @Test("Aenderungen erkennen; Seite wechseln waehlt ab")
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
