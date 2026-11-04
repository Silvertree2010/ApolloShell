import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Editing: managing the pages in the working copy")
struct BentoEditSessionPageTests {
    private func session() throws -> BentoEditSession {
        let a = DashboardPage(name: "A", symbol: "star")
        let b = DashboardPage(name: "B", symbol: "moon")
        let pages = try #require(DashboardPages(pages: [a, b]))
        return BentoEditSession(pages: pages, pageID: a.id)
    }

    @Test("A new page: at the end, shown right away")
    func addPage() throws {
        var s = try session()
        let id = s.addPage(name: "New")
        #expect(s.pages.pages.last?.id == id)
        #expect(s.pageID == id)
        #expect(s.pages.pages.count == 3)
    }

    @Test("A copy: right behind the original, shown right away")
    func duplicatePage() throws {
        var s = try session()
        let originalID = s.pageID
        let duplicated = s.duplicatePage(originalID, name: "A Copy")
        let copyID = try #require(duplicated)
        #expect(s.pageID == copyID)
        #expect(s.pages.pages[1].id == copyID)
        #expect(s.pages.pages[1].name == "A Copy")
    }

    @Test("Deleting: never the last page")
    func removeLastPage() throws {
        let a = DashboardPage(name: "A", symbol: "star")
        let pages = try #require(DashboardPages(pages: [a]))
        var s = BentoEditSession(pages: pages, pageID: a.id)
        let removed = s.removePage(a.id)
        #expect(!removed)
        #expect(s.pages.pages.count == 1)
    }

    @Test("Deleting the shown page shows its neighbour")
    func removeShownPage() throws {
        var s = try session()
        let aID = s.pageID
        let bID = s.pages.pages[1].id
        let removed = s.removePage(aID)
        #expect(removed)
        #expect(s.pages.pages.count == 1)
        #expect(s.pageID == bID)
    }

    @Test("Deleting a page that is not shown does not change the selection")
    func removeOtherPage() throws {
        var s = try session()
        let aID = s.pageID
        let bID = s.pages.pages[1].id
        let removed = s.removePage(bID)
        #expect(removed)
        #expect(s.pageID == aID)
    }

    @Test("Renaming, the symbol, the order")
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

    @Test("Restoring the default pages: only appends the templates that are missing, switches nothing")
    func restoreDefaults() throws {
        var s = try session()
        let shownBefore = s.pageID
        let countBefore = s.pages.pages.count
        let defaults = DashboardPages.defaultPages(places: .empty, hasBattery: false)
        s.restoreDefaults(from: defaults)
        // A and B have no template - all four pages that ship with the app are still missing.
        #expect(s.pages.pages.count == countBefore + defaults.count)
        #expect(s.pageID == shownBefore)
        // A second call appends nothing more - all the templates are there now.
        s.restoreDefaults(from: defaults)
        #expect(s.pages.pages.count == countBefore + defaults.count)
    }
}
