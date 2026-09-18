import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Widget-Katalog: Kennungen und Groessen von vor 0.2")
struct WidgetCatalogTests {
    private func text(_ sizes: [WidgetSize]) -> String {
        sizes.map { s in s.isFlexible ? "\(Int(s.minWidth))-\(Int(s.maxWidth))x\(Int(s.height))" : "\(Int(s.minWidth))x\(Int(s.height))" }
            .joined(separator: " ")
    }

    @Test("Kennungen stehen in settings.json und aendern sich nie")
    func rawValues() {
        #expect(WidgetKind.allCases.map(\.rawValue) == [
            "weather", "user", "clock", "calendar", "resources", "media",
            "performance.cpu", "performance.gpu", "performance.storage", "performance.network",
            "performance.memory", "performance.battery",
            "weather.hero", "weather.hourly", "weather.daily", "media.player",
        ])
    }

    @Test("Jede Karte der Uebersicht ist ein Widget mit derselben Kennung")
    func cardsMap() {
        for card in DashboardCardKind.allCases {
            #expect(WidgetKind(card).overviewCard == card)
        }
    }

    @Test("Groessen der Uebersicht", arguments: [
        (WidgetKind.weather, "275-839x130 200-839x250 200-839x392"),
        (.user, "230-839x130 200-839x250 200-839x392"),
        (.clock, "110-839x130 110-839x250 110-839x392"),
        (.calendar, "300-839x250 300-839x392"),
        (.resources, "230-839x130 90-839x250 90-839x392"),
        (.media, "300-839x130 200-839x250 200-839x392"),
    ])
    func overviewSizes(kind: WidgetKind, expected: String) {
        #expect(text(kind.sizes) == expected)
    }

    @Test("Groessen der Seiten Leistung, Wetter, Medien", arguments: [
        (WidgetKind.performanceCPU, "343-414x191"),
        (.performanceGPU, "343-414x191"),
        (.performanceStorage, "169-240x189"),
        (.performanceNetwork, "335x189"),
        (.performanceMemory, "169-240x189"),
        (.performanceBattery, "129x392"),
        (.weatherHero, "839x116"),
        (.weatherHourly, "839x108"),
        (.weatherDaily, "839x144"),
        (.mediaPlayer, "839x392"),
    ])
    func pageSizes(kind: WidgetKind, expected: String) {
        #expect(text(kind.sizes) == expected)
    }

    @Test("Jede Karte jeder Vorlage und jedes Rasters von vor 0.2 hat eine erlaubte Groesse")
    func placementsAreAllowed() {
        var layouts = DashboardPreset.allCases.map(\.layout.cards)
        layouts += [
            DashboardCards(top: [.weather], bottom: [], side: []),
            DashboardCards(top: [], bottom: [.clock, .resources], side: []),
            DashboardCards(top: [], bottom: [], side: [.media]),
            DashboardCards(top: [.resources, .clock], bottom: [.media, .weather, .user], side: [.calendar]),
        ]
        for cards in layouts {
            for placement in DashboardGeometry.placements(for: cards) {
                let kind = WidgetKind(placement.card.kind)
                #expect(kind.allows(width: placement.frame.width, height: placement.frame.height),
                        "\(kind.rawValue) \(placement.frame)")
            }
        }
    }

    @Test("Kleinste Groesse nach Flaeche")
    func smallest() {
        #expect(WidgetKind.clock.smallestSize == .flexible(110, 839, 130))
        #expect(WidgetKind.resources.smallestSize == .flexible(90, 839, 250))
        #expect(WidgetKind.mediaPlayer.smallestSize == .fixed(839, 392))
    }

    @Test("Heimat, Orte, Medien")
    func flags() {
        #expect(WidgetKind.allCases.allSatisfy { $0.home == .dashboard })
        #expect(WidgetKind.allCases.filter(\.usesPlaces) == [.weather, .weatherHero, .weatherHourly, .weatherDaily])
        #expect(WidgetKind.allCases.filter(\.usesMedia) == [.media, .mediaPlayer])
        #expect(WidgetKind.allCases.filter(\.isPerformance).count == 6)
    }

    @Test("Masse der Seite Leistung: mit Akku schmaler")
    func performanceGeometry() {
        #expect(PerformancePageGeometry.heroHeight == 191)
        #expect(PerformancePageGeometry.heroWidths(hasBattery: true) == [343, 343])
        #expect(PerformancePageGeometry.heroWidths(hasBattery: false) == [413, 414])
        #expect(PerformancePageGeometry.sideWidths(hasBattery: true) == [169, 170])
        #expect(PerformancePageGeometry.sideWidths(hasBattery: false) == [240, 240])
        #expect(WeatherPageGeometry.dailyHeight == 144)
    }
}
