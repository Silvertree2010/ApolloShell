import Foundation

// The bundled pages (the four tabs from before 0.2, exactly) and
// the one-time migration of settings from 0.1.x.

public extension PageTemplate {
    /// The bundled page in the shape it had before 0.2. `places`: locations of
    /// the weather widgets (during migration, the favorites from weather.json);
    /// `hasBattery`: performance page with battery on the right, or without.
    func defaultPage(places: WeatherFavorites, hasBattery: Bool) -> DashboardPage {
        DashboardPage(name: tab.title, symbol: tab.symbol, template: self,
                      widgets: defaultWidgets(places: places, hasBattery: hasBattery))
    }

    internal func defaultWidgets(places: WeatherFavorites, hasBattery: Bool) -> [WidgetInstance] {
        let width = DashboardGeometry.width
        let spacing = DashboardGeometry.spacing
        switch self {
        case .overview:
            return DashboardPages.overviewWidgets(.caelestia, places: places)
        case .media:
            return [WidgetInstance(kind: .mediaPlayer, frame: WidgetFrame(x: 0, y: 0, width: width, height: DashboardGeometry.height))]
        case .weather:
            let g = WeatherPageGeometry.self
            func widget(_ kind: WidgetKind, y: Double, height: Double) -> WidgetInstance {
                WidgetInstance(kind: kind, frame: WidgetFrame(x: 0, y: y, width: width, height: height),
                               options: .defaults(for: kind, places: places))
            }
            return [
                widget(.weatherHero, y: 0, height: g.heroHeight),
                widget(.weatherHourly, y: g.heroHeight + g.spacing, height: g.hourlyHeight),
                widget(.weatherDaily, y: g.heroHeight + g.hourlyHeight + 2 * g.spacing, height: g.dailyHeight),
            ]
        case .performance:
            let p = PerformancePageGeometry.self
            let hero = p.heroWidths(hasBattery: hasBattery)
            let side = p.sideWidths(hasBattery: hasBattery)
            let bottomY = p.heroHeight + spacing
            var result = [
                WidgetInstance(kind: .performanceCPU, frame: WidgetFrame(x: 0, y: 0, width: hero[0], height: p.heroHeight)),
                WidgetInstance(kind: .performanceGPU, frame: WidgetFrame(x: hero[0] + spacing, y: 0, width: hero[1], height: p.heroHeight)),
                WidgetInstance(kind: .performanceStorage, frame: WidgetFrame(x: 0, y: bottomY, width: side[0], height: p.bottomHeight)),
                WidgetInstance(kind: .performanceNetwork, frame: WidgetFrame(x: side[0] + spacing, y: bottomY,
                                                                             width: p.networkWidth, height: p.bottomHeight)),
                WidgetInstance(kind: .performanceMemory, frame: WidgetFrame(x: side[0] + spacing + p.networkWidth + spacing,
                                                                            y: bottomY, width: side[1], height: p.bottomHeight)),
            ]
            if hasBattery {
                result.append(WidgetInstance(kind: .performanceBattery,
                                             frame: WidgetFrame(x: p.leftWidth(hasBattery: true) + spacing, y: 0,
                                                                width: p.batteryWidth, height: DashboardGeometry.height)))
            }
            return result
        }
    }
}

public extension DashboardPages {
    /// The four bundled pages in the order of the tabs from before 0.2.
    static func defaultPages(places: WeatherFavorites, hasBattery: Bool) -> [DashboardPage] {
        PageTemplate.allCases.map { $0.defaultPage(places: places, hasBattery: hasBattery) }
    }

    /// Migration on the first launch of 0.2: the visible tabs in their
    /// order, the overview with exactly its cards and options at
    /// exactly their places. Hidden tabs don't come along
    /// ("Restore Default Pages" brings them back).
    static func migrated(from layout: DashboardLayout, places: WeatherFavorites, hasBattery: Bool) -> DashboardPages {
        let pages = layout.tabs.visible.map { tab -> DashboardPage in
            let template = PageTemplate(tab)
            guard template == .overview else { return template.defaultPage(places: places, hasBattery: hasBattery) }
            return DashboardPage(name: tab.title, symbol: tab.symbol, template: .overview,
                                 widgets: overviewWidgets(layout.cards, places: places))
        }
        // `visible` is never empty (DashboardTabs); the defaults as a safety net anyway.
        return DashboardPages(pages: pages) ?? DashboardPages(pages: defaultPages(places: places, hasBattery: hasBattery))!
    }

    /// Cards of the overview as widgets, at the frames from
    /// `DashboardGeometry.placements` and with their options.
    internal static func overviewWidgets(_ cards: DashboardCards, places: WeatherFavorites) -> [WidgetInstance] {
        DashboardGeometry.placements(for: cards).map { placement in
            let kind = WidgetKind(placement.card.kind)
            var options = WidgetOptions.defaults(for: kind, places: places)
            switch placement.card {
            case .weather(let o): options.weather = o
            case .user(let o): options.user = o
            case .clock(let o): options.clock = o
            case .calendar(let o): options.calendar = o
            case .resources(let o): options.resources = o
            case .media(let o): options.media = o
            }
            return WidgetInstance(kind: kind, frame: WidgetFrame(placement.frame), options: options)
        }
    }
}
