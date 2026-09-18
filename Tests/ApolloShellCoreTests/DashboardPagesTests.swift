import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Dashboard-Seiten: Widgets auf der Seite, Seitenverwaltung, Lesen")
struct DashboardPagesTests {
    private func f(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> WidgetFrame {
        WidgetFrame(x: x, y: y, width: w, height: h)
    }
    private func clock(_ frame: WidgetFrame) -> WidgetInstance { WidgetInstance(kind: .clock, frame: frame) }

    @Test("Seite behaelt nur gueltige Widgets, in Reihenfolge")
    func normalizes() {
        let a = clock(f(0, 0, 110, 130))
        let tooClose = clock(f(115, 0, 110, 130))
        let wrongSize = clock(f(300, 0, 100, 130))
        let outside = clock(f(800, 0, 110, 130))
        let b = clock(f(122, 0, 110, 130))
        let page = DashboardPage(name: "X", symbol: "star", widgets: [a, tooClose, wrongSize, outside, b, a])
        #expect(page.widgets.map(\.id) == [a.id, b.id])
    }

    @Test("Widget hinzufuegen, verschieben, entfernen: Ungueltiges aendert nichts")
    func widgetEdits() {
        var page = DashboardPage(name: "X", symbol: "star")
        let a = clock(f(0, 0, 110, 130))
        #expect(page.add(a) == true)
        #expect(page.add(clock(f(100, 0, 110, 130))) == false)
        #expect(page.setFrame(f(0, 0, 200, 250), for: a.id) == true)
        #expect(page.setFrame(f(0, 0, 50, 250), for: a.id) == false)
        #expect(page.widgets[0].frame == f(0, 0, 200, 250))
        page.setOptions(WidgetOptions(clock: DashboardClockOptions(showDate: true)), for: a.id)
        #expect(page.widgets[0].options.clock?.showDate == true)
        page.removeWidget(id: a.id)
        #expect(page.widgets.isEmpty)
    }

    @Test("Seiten: nie leer, letzte nicht loeschbar, Kopie hinter das Original mit neuen Kennungen")
    func pageEdits() throws {
        let first = DashboardPage(name: "A", symbol: "star", template: .overview, widgets: [clock(f(0, 0, 110, 130))])
        #expect(DashboardPages(pages: []) == nil)
        var pages = try #require(DashboardPages(pages: [first]))
        #expect(pages.removePage(id: first.id) == false)
        let added = pages.addPage(name: "B")
        #expect(pages.pages.map(\.name) == ["A", "B"])
        let duplicated = pages.duplicatePage(id: first.id, name: "A Kopie")
        let copyID = try #require(duplicated)
        #expect(pages.pages.map(\.name) == ["A", "A Kopie", "B"])
        let copy = try #require(pages.page(id: copyID))
        #expect(copy.template == nil)
        #expect(copy.widgets.count == 1)
        #expect(copy.widgets[0].id != first.widgets[0].id)
        pages.renamePage(id: added, to: "Neu")
        pages.setSymbol("bolt", forPage: added)
        pages.movePages(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(pages.pages.map(\.name) == ["Neu", "A", "A Kopie"])
        #expect(pages.pages[0].symbol == "bolt")
        #expect(pages.removePage(id: added) == true)
    }

    @Test("Wiederherstellen haengt nur fehlende Vorlagen an")
    func restore() throws {
        let overview = DashboardPage(name: "Mein Dashboard", symbol: "star", template: .overview)
        var pages = try #require(DashboardPages(pages: [overview]))
        let defaults = PageTemplate.allCases.map { DashboardPage(name: $0.rawValue, symbol: "x", template: $0) }
        pages.restoreDefaults(from: defaults)
        #expect(pages.pages.map(\.name) == ["Mein Dashboard", "media", "performance", "weather"])
    }

    @Test("Knopf fuer eine Seite: Vorlage, sonst erstes passendes Widget, sonst erste Seite")
    func resolve() throws {
        let own = DashboardPage(name: "Eigene", symbol: "star")
        var withMedia = DashboardPage(name: "Musik", symbol: "star")
        #expect(withMedia.add(WidgetInstance(kind: .media, frame: f(0, 0, 300, 130))) == true)
        let mediaPage = DashboardPage(name: "Medien", symbol: "x", template: .media)
        let all = try #require(DashboardPages(pages: [own, withMedia, mediaPage]))
        #expect(all.page(for: .media, showing: [.media, .mediaPlayer]).name == "Medien")
        let noTemplate = try #require(DashboardPages(pages: [own, withMedia]))
        #expect(noTemplate.page(for: .media, showing: [.media, .mediaPlayer]).name == "Musik")
        #expect(noTemplate.page(for: .weather, showing: [.weatherHero]).name == "Eigene")
        #expect(noTemplate.usesMedia)
        #expect(!noTemplate.usesWeather)
    }

    @Test("Lesen: kaputte Seiten und Widgets fallen weg, leere Liste ist nicht lesbar")
    func decoding() throws {
        let json = #"""
        [{"id":"00000000-0000-0000-0000-00000000000A","name":"A","template":"overview",
          "widgets":[{"kind":"clock","frame":{"x":0,"y":0,"width":110,"height":130}},{"kind":"toaster"}]},
         5,
         {"name":"B","template":"nope"}]
        """#
        let pages = try JSONDecoder().decode(DashboardPages.self, from: Data(json.utf8))
        #expect(pages.pages.map(\.name) == ["A", "B"])
        #expect(pages.pages[0].widgets.map(\.kind) == [.clock])
        #expect(pages.pages[1].template == nil)
        #expect(pages.pages[1].symbol == DashboardPage.defaultSymbol)
        #expect((try? JSONDecoder().decode(DashboardPages.self, from: Data("[]".utf8))) == nil)
        let data = try JSONEncoder().encode(pages)
        #expect(try JSONDecoder().decode(DashboardPages.self, from: data) == pages)
    }
}
