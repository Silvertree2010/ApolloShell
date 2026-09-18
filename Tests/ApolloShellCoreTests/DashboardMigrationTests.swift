import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Umzug von 0.1.x und mitgelieferte Seiten")
struct DashboardMigrationTests {
    private let chur = WeatherLocation(name: "Chur", latitude: 46.85, longitude: 9.53)
    private var places: WeatherFavorites { WeatherFavorites(locations: [chur], selectedID: chur.id) }

    private func frames(_ page: DashboardPage) -> [String] {
        page.widgets.map { "\($0.kind.rawValue) \(Int($0.frame.x)),\(Int($0.frame.y)) \(Int($0.frame.width))x\(Int($0.frame.height))" }
    }

    @Test("Uebersicht: jede Vorlage von vor 0.2 landet punktgenau", arguments: DashboardPreset.allCases)
    func overviewExact(preset: DashboardPreset) {
        let layout = preset.layout
        let pages = DashboardPages.migrated(from: layout, places: places, hasBattery: true)
        let overview = pages.pages.first { $0.template == .overview }
        let expected = DashboardGeometry.placements(for: layout.cards).map {
            "\($0.card.kind.rawValue) \(Int($0.frame.x)),\(Int($0.frame.y)) \(Int($0.frame.width))x\(Int($0.frame.height))"
        }
        #expect(overview.map(frames) == expected)
    }

    @Test("Caelestia-Uebersicht, Zahl fuer Zahl")
    func caelestiaNumbers() {
        let page = PageTemplate.overview.defaultPage(places: places, hasBattery: true)
        #expect(frames(page) == [
            "weather 0,0 275x130", "user 287,0 340x130",
            "clock 0,142 110x250", "calendar 122,142 403x250", "resources 537,142 90x250",
            "media 639,0 200x392",
        ])
    }

    @Test("Reihenfolge und Sichtbarkeit der Reiter, Optionen der Karten, Orte")
    func tabsAndOptions() {
        var cards = DashboardCards.caelestia
        cards.update(.clock(DashboardClockOptions(style: .inline, showDate: true)))
        let layout = DashboardLayout(tabs: DashboardTabs(order: [.weather, .dashboard, .media, .performance], hidden: [.media]),
                                     cards: cards)
        let pages = DashboardPages.migrated(from: layout, places: places, hasBattery: true)
        #expect(pages.pages.map(\.template) == [.weather, .overview, .performance])
        #expect(pages.pages.map(\.name) == [DashboardTab.weather.title, DashboardTab.dashboard.title, DashboardTab.performance.title])
        let clock = pages.pages[1].widgets.first { $0.kind == .clock }
        #expect(clock?.options.clock == DashboardClockOptions(style: .inline, showDate: true))
        #expect(pages.pages[1].widgets.first { $0.kind == .weather }?.options.places == places)
        #expect(pages.pages[0].widgets.allSatisfy { $0.options.places == places })
    }

    @Test("Seite Leistung mit und ohne Akku")
    func performance() {
        #expect(frames(PageTemplate.performance.defaultPage(places: .empty, hasBattery: true)) == [
            "performance.cpu 0,0 343x191", "performance.gpu 355,0 343x191",
            "performance.storage 0,203 169x189", "performance.network 181,203 335x189",
            "performance.memory 528,203 170x189", "performance.battery 710,0 129x392",
        ])
        #expect(frames(PageTemplate.performance.defaultPage(places: .empty, hasBattery: false)) == [
            "performance.cpu 0,0 413x191", "performance.gpu 425,0 414x191",
            "performance.storage 0,203 240x189", "performance.network 252,203 335x189",
            "performance.memory 599,203 240x189",
        ])
    }

    @Test("Seiten Wetter und Medien")
    func weatherAndMedia() {
        #expect(frames(PageTemplate.weather.defaultPage(places: places, hasBattery: true)) == [
            "weather.hero 0,0 839x116", "weather.hourly 0,128 839x108", "weather.daily 0,248 839x144",
        ])
        #expect(frames(PageTemplate.media.defaultPage(places: places, hasBattery: true)) == ["media.player 0,0 839x392"])
    }

    @Test("Vorgaben: vier Seiten in der Reihenfolge von vor 0.2, mit Namen und Symbolen der Reiter")
    func defaults() {
        let pages = DashboardPages.defaultPages(places: places, hasBattery: true)
        #expect(pages.map(\.template) == [.overview, .media, .performance, .weather])
        #expect(pages.map(\.symbol) == DashboardTab.allCases.map(\.symbol))
    }
}
