import Foundation
import Testing
@testable import ApolloShellCore

@Suite("The migration from 0.1.x and the pages that ship with the app")
struct DashboardMigrationTests {
    private let chur = WeatherLocation(name: "Chur", latitude: 46.85, longitude: 9.53)
    private var places: WeatherFavorites { WeatherFavorites(locations: [chur], selectedID: chur.id) }

    /// A whole number without a decimal, a half point (performance without a
    /// battery) with exactly one.
    private func format(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : "\(value)"
    }

    private func frames(_ page: DashboardPage) -> [String] {
        page.widgets.map {
            "\($0.kind.rawValue) \(format($0.frame.x)),\(format($0.frame.y)) \(format($0.frame.width))x\(format($0.frame.height))"
        }
    }

    @Test("The overview: every template from before 0.2 lands point for point", arguments: DashboardPreset.allCases)
    func overviewExact(preset: DashboardPreset) {
        let layout = preset.layout
        let pages = DashboardPages.migrated(from: layout, places: places, hasBattery: true)
        let overview = pages.pages.first { $0.template == .overview }
        let expected = DashboardGeometry.placements(for: layout.cards).map {
            "\($0.card.kind.rawValue) \(Int($0.frame.x)),\(Int($0.frame.y)) \(Int($0.frame.width))x\(Int($0.frame.height))"
        }
        #expect(overview.map(frames) == expected)
    }

    @Test("The Caelestia overview, number for number")
    func caelestiaNumbers() {
        let page = PageTemplate.overview.defaultPage(places: places, hasBattery: true)
        #expect(frames(page) == [
            "weather 0,0 275x130", "user 287,0 340x130",
            "clock 0,142 110x250", "calendar 122,142 403x250", "resources 537,142 90x250",
            "media 639,0 200x392",
        ])
    }

    @Test("The order and the visibility of the tabs, the options of the cards, the places")
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

    @Test("The performance page with and without a battery")
    func performance() {
        #expect(frames(PageTemplate.performance.defaultPage(places: .empty, hasBattery: true)) == [
            "performance.cpu 0,0 343x191", "performance.gpu 355,0 343x191",
            "performance.storage 0,203 169.5x189", "performance.network 181.5,203 335x189",
            "performance.memory 528.5,203 169.5x189", "performance.battery 710,0 129x392",
        ])
        #expect(frames(PageTemplate.performance.defaultPage(places: .empty, hasBattery: false)) == [
            "performance.cpu 0,0 413.5x191", "performance.gpu 425.5,0 413.5x191",
            "performance.storage 0,203 240x189", "performance.network 252,203 335x189",
            "performance.memory 599,203 240x189",
        ])
    }

    @Test("The weather and media pages")
    func weatherAndMedia() {
        #expect(frames(PageTemplate.weather.defaultPage(places: places, hasBattery: true)) == [
            "weather.hero 0,0 839x116", "weather.hourly 0,128 839x108", "weather.daily 0,248 839x144",
        ])
        #expect(frames(PageTemplate.media.defaultPage(places: places, hasBattery: true)) == ["media.player 0,0 839x392"])
    }

    @Test("The defaults: four pages in the order from before 0.2, with the names and symbols of the tabs")
    func defaults() {
        let pages = DashboardPages.defaultPages(places: places, hasBattery: true)
        #expect(pages.map(\.template) == [.overview, .media, .performance, .weather])
        #expect(pages.map(\.symbol) == DashboardTab.allCases.map(\.symbol))
    }
}
