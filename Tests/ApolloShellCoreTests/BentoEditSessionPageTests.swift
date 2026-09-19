import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Bearbeiten: Seitenverwaltung in der Arbeitskopie")
struct BentoEditSessionPageTests {
    private func session() throws -> BentoEditSession {
        let a = DashboardPage(name: "A", symbol: "star")
        let b = DashboardPage(name: "B", symbol: "moon")
        let pages = try #require(DashboardPages(pages: [a, b]))
        return BentoEditSession(pages: pages, pageID: a.id)
    }

    @Test("Neue Seite: ans Ende, sofort gezeigt")
    func addPage() throws {
        var s = try session()
        let id = s.addPage(name: "Neu")
        #expect(s.pages.pages.last?.id == id)
        #expect(s.pageID == id)
        #expect(s.pages.pages.count == 3)
    }

    @Test("Kopie: direkt hinter dem Original, sofort gezeigt")
    func duplicatePage() throws {
        var s = try session()
        let originalID = s.pageID
        let duplicated = s.duplicatePage(originalID, name: "A Kopie")
        let copyID = try #require(duplicated)
        #expect(s.pageID == copyID)
        #expect(s.pages.pages[1].id == copyID)
        #expect(s.pages.pages[1].name == "A Kopie")
    }

    @Test("Loeschen: nie die letzte Seite")
    func removeLastPage() throws {
        let a = DashboardPage(name: "A", symbol: "star")
        let pages = try #require(DashboardPages(pages: [a]))
        var s = BentoEditSession(pages: pages, pageID: a.id)
        let removed = s.removePage(a.id)
        #expect(!removed)
        #expect(s.pages.pages.count == 1)
    }

    @Test("Loeschen der gezeigten Seite zeigt ihre Nachbarin")
    func removeShownPage() throws {
        var s = try session()
        let aID = s.pageID
        let bID = s.pages.pages[1].id
        let removed = s.removePage(aID)
        #expect(removed)
        #expect(s.pages.pages.count == 1)
        #expect(s.pageID == bID)
    }

    @Test("Loeschen einer nicht gezeigten Seite aendert die Auswahl nicht")
    func removeOtherPage() throws {
        var s = try session()
        let aID = s.pageID
        let bID = s.pages.pages[1].id
        let removed = s.removePage(bID)
        #expect(removed)
        #expect(s.pageID == aID)
    }

    @Test("Umbenennen, Symbol, Reihenfolge")
    func renameSymbolMove() throws {
        var s = try session()
        let aID = s.pageID
        s.renamePage(aID, to: "Anders")
        #expect(s.pages.pages[0].name == "Anders")
        s.setSymbol("heart", forPage: aID)
        #expect(s.pages.pages[0].symbol == "heart")
        s.movePages(fromOffsets: [0], toOffset: 2)
        #expect(s.pages.pages[0].name == "B")
        #expect(s.pages.pages[1].name == "Anders")
    }
}
