import Foundation

// Die mitgelieferten Seiten (die vier Reiter von vor 0.2, punktgenau) und
// der einmalige Umzug der Einstellungen von 0.1.x.

public extension PageTemplate {
    /// Die mitgelieferte Seite in der Form von vor 0.2. `places`: Orte der
    /// Wetter-Widgets (beim Umzug die Favoriten aus weather.json);
    /// `hasBattery`: Seite Leistung mit Akku rechts oder ohne.
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
    /// Die vier mitgelieferten Seiten in der Reihenfolge der Reiter von vor 0.2.
    static func defaultPages(places: WeatherFavorites, hasBattery: Bool) -> [DashboardPage] {
        PageTemplate.allCases.map { $0.defaultPage(places: places, hasBattery: hasBattery) }
    }

    /// Umzug beim ersten Start von 0.2: die sichtbaren Reiter in ihrer
    /// Reihenfolge, die Uebersicht mit genau ihren Karten und Optionen an
    /// genau ihren Plaetzen. Ausgeblendete Reiter kommen nicht mit
    /// ("Standardseiten wiederherstellen" holt sie zurueck).
    static func migrated(from layout: DashboardLayout, places: WeatherFavorites, hasBattery: Bool) -> DashboardPages {
        let pages = layout.tabs.visible.map { tab -> DashboardPage in
            let template = PageTemplate(tab)
            guard template == .overview else { return template.defaultPage(places: places, hasBattery: hasBattery) }
            return DashboardPage(name: tab.title, symbol: tab.symbol, template: .overview,
                                 widgets: overviewWidgets(layout.cards, places: places))
        }
        // `visible` ist nie leer (DashboardTabs); zur Sicherheit trotzdem die Vorgaben.
        return DashboardPages(pages: pages) ?? DashboardPages(pages: defaultPages(places: places, hasBattery: hasBattery))!
    }

    /// Karten der Uebersicht als Widgets, an den Rahmen von
    /// `DashboardGeometry.placements` und mit ihren Optionen.
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
