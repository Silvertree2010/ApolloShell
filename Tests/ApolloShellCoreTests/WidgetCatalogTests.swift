import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Widget catalog: identifiers and sizes from before 0.2")
struct WidgetCatalogTests {
    /// Whole number without decimal, a half point (performance without battery)
    /// with exactly one.
    private func format(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : "\(value)"
    }

    private func text(_ sizes: [WidgetSize]) -> String {
        sizes.map { s in
            s.isFlexible ? "\(format(s.minWidth))-\(format(s.maxWidth))x\(format(s.height))"
                         : "\(format(s.minWidth))x\(format(s.height))"
        }
        .joined(separator: " ")
    }

    @Test("identifiers live in settings.json and never change")
    func rawValues() {
        #expect(WidgetKind.allCases.map(\.rawValue) == [
            "weather", "user", "clock", "calendar", "resources", "media",
            "performance.cpu", "performance.gpu", "performance.storage", "performance.network",
            "performance.memory", "performance.battery",
            "weather.hero", "weather.hourly", "weather.daily", "media.player",
            "timer", "apps", "photos", "network.info", "files.recent", "clipboard", "sun", "drives",
        ])
    }

    @Test("Every overview card is a widget with the same identifier")
    func cardsMap() {
        for card in DashboardCardKind.allCases {
            #expect(WidgetKind(card).overviewCard == card)
        }
    }

    @Test("Overview sizes", arguments: [
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

    @Test("Sizes of the performance, weather, and media pages: their own plus the overview heights", arguments: [
        (WidgetKind.performanceCPU, "220-839x130 343-839x191 250-839x250 250-839x392"),
        (.performanceGPU, "220-839x130 343-839x191 250-839x250 250-839x392"),
        (.performanceStorage, "200-839x130 169.5-420x189 169.5-420x250 169.5-420x392"),
        (.performanceNetwork, "230-839x130 335-839x189 300-839x250 300-839x392"),
        (.performanceMemory, "200-839x130 169.5-420x189 169.5-420x250 169.5-420x392"),
        (.performanceBattery, "129-420x130 129-420x250 129-420x392"),
        (.weatherHero, "500-839x116 275-839x250 275-839x392"),
        (.weatherHourly, "300-839x108 300-839x250"),
        (.weatherDaily, "300-839x144 275-839x250 200-839x392"),
        (.mediaPlayer, "413-839x250 413-839x392"),
    ])
    func pageSizes(kind: WidgetKind, expected: String) {
        #expect(text(kind.sizes) == expected)
    }

    @Test("Every card of every template and every grid from before 0.2 has an allowed size")
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

    @Test("Smallest size by area")
    func smallest() {
        #expect(WidgetKind.clock.smallestSize == .flexible(110, 839, 130))
        #expect(WidgetKind.resources.smallestSize == .flexible(90, 839, 250))
        #expect(WidgetKind.mediaPlayer.smallestSize == .flexible(413, 839, 250))
    }

    @Test("Home, places, media")
    func flags() {
        #expect(WidgetKind.allCases.allSatisfy { $0.home == .dashboard })
        #expect(WidgetKind.allCases.filter(\.usesPlaces) == [.weather, .weatherHero, .weatherHourly, .weatherDaily])
        #expect(WidgetKind.allCases.filter(\.hasPlaces) == [.weather, .weatherHero, .weatherHourly, .weatherDaily, .sun])
        #expect(WidgetKind.allCases.filter(\.usesMedia) == [.media, .mediaPlayer])
        #expect(WidgetKind.allCases.filter(\.isPerformance).count == 6)
    }

    @Test("Dimensions of the performance page: narrower with a battery")
    func performanceGeometry() {
        #expect(PerformancePageGeometry.heroHeight == 191)
        #expect(PerformancePageGeometry.heroWidths(hasBattery: true) == [343, 343])
        #expect(PerformancePageGeometry.heroWidths(hasBattery: false) == [413.5, 413.5])
        #expect(PerformancePageGeometry.sideWidths(hasBattery: true) == [169.5, 169.5])
        #expect(PerformancePageGeometry.sideWidths(hasBattery: false) == [240, 240])
        #expect(WeatherPageGeometry.dailyHeight == 144)
    }

    @Test("Every size of the page templates stays allowed, and one size per height")
    func pageTemplatesStayAllowed() {
        for hasBattery in [true, false] {
            let pages = DashboardPages.defaultPages(places: .empty, hasBattery: hasBattery)
            for widget in pages.flatMap(\.widgets) {
                #expect(widget.kind.allows(width: widget.frame.width, height: widget.frame.height),
                        "\(widget.kind.rawValue) \(widget.frame)")
            }
        }
        for kind in WidgetKind.allCases {
            #expect(Set(kind.sizes.map(\.height)).count == kind.sizes.count, "\(kind.rawValue)")
        }
    }

    @Test("Every kind has displays, the first is the standard one")
    func displays() {
        for kind in WidgetKind.allCases {
            #expect(kind.displays.first == .standard, "\(kind.rawValue)")
            #expect(Set(kind.displays).count == kind.displays.count)
        }
    }
}
