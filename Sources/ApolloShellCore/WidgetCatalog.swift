import Foundation

// Katalog der Widgets fuer das Bento-Dashboard (0.2, siehe
// design/2026-09-18-bento-dashboard.md). Jedes Widget ist hier einmal
// beschrieben: Kennung, Name, Symbol, Heimat, erlaubte Groessen. Die Groessen
// sind genau die, die das Dashboard vor 0.2 zeichnen konnte.

/// Wo ein Widget zuhause ist. Ausserhalb der Heimat nur als erweiterte
/// Option in Nexus, dort nicht optimiert.
public enum WidgetSurface: String, Codable, CaseIterable, Sendable {
    case dashboard, controlCentre
}

/// Eine erlaubte Groesse in Referenzpunkten (Seite 839 x 392). Feste Breite:
/// `minWidth == maxWidth`. Die Hoehe ist immer fest.
public struct WidgetSize: Equatable, Hashable, Sendable {
    public var minWidth: Double
    public var maxWidth: Double
    public var height: Double

    public init(minWidth: Double, maxWidth: Double, height: Double) {
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.height = height
    }

    public static func fixed(_ width: Double, _ height: Double) -> WidgetSize {
        WidgetSize(minWidth: width, maxWidth: width, height: height)
    }

    public static func flexible(_ minWidth: Double, _ maxWidth: Double, _ height: Double) -> WidgetSize {
        WidgetSize(minWidth: minWidth, maxWidth: maxWidth, height: height)
    }

    public var isFlexible: Bool { maxWidth > minWidth }

    public func allows(width: Double, height: Double) -> Bool {
        height == self.height && width >= minWidth && width <= maxWidth
    }
}

/// Alle Widgets. Rohwert steht in settings.json - nie umbenennen. Die sechs
/// Karten der Uebersicht behalten die Kennungen von `DashboardCardKind`.
public enum WidgetKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case weather, user, clock, calendar, resources, media
    case performanceCPU = "performance.cpu"
    case performanceGPU = "performance.gpu"
    case performanceStorage = "performance.storage"
    case performanceNetwork = "performance.network"
    case performanceMemory = "performance.memory"
    case performanceBattery = "performance.battery"
    case weatherHero = "weather.hero"
    case weatherHourly = "weather.hourly"
    case weatherDaily = "weather.daily"
    case mediaPlayer = "media.player"

    public var id: Self { self }

    public init(_ card: DashboardCardKind) {
        // Gleiche Rohwerte, der Test `cardsMap` haelt das fest.
        self = WidgetKind(rawValue: card.rawValue)!
    }

    /// Die Karte von vor 0.2, falls das Widget eine ist.
    public var overviewCard: DashboardCardKind? { DashboardCardKind(rawValue: rawValue) }

    public var title: String {
        if let card = overviewCard { return card.title }
        return switch self {
        case .performanceCPU: "CPU"
        case .performanceGPU: "GPU"
        case .performanceStorage: String(localized: "Speicher")
        case .performanceNetwork: String(localized: "Netzwerk")
        case .performanceMemory: String(localized: "Arbeitsspeicher")
        case .performanceBattery: String(localized: "Akku")
        case .weatherHero: String(localized: "Wetterübersicht")
        case .weatherHourly: String(localized: "Stündlich")
        case .weatherDaily: String(localized: "Nächste Tage")
        case .mediaPlayer: String(localized: "Wiedergabe")
        case .weather, .user, .clock, .calendar, .resources, .media: ""
        }
    }

    public var symbol: String {
        if let card = overviewCard { return card.symbol }
        return switch self {
        case .performanceCPU: "cpu"
        case .performanceGPU: "square.stack.3d.up"
        case .performanceStorage: "internaldrive"
        case .performanceNetwork: "network"
        case .performanceMemory: "memorychip"
        case .performanceBattery: "battery.75percent"
        case .weatherHero: "cloud.sun"
        case .weatherHourly: "clock"
        case .weatherDaily: "calendar"
        case .mediaPlayer: "play.rectangle"
        case .weather, .user, .clock, .calendar, .resources, .media: "questionmark"
        }
    }

    /// Alle heutigen Widgets gehoeren ins Dashboard; das Control Centre
    /// bekommt seine eigenen erst mit dem Editor fuer alle Flaechen.
    public var home: WidgetSurface { .dashboard }

    /// Wetter-Widgets tragen ihre eigene Liste an Orten (`WidgetOptions.places`).
    public var usesPlaces: Bool {
        switch self {
        case .weather, .weatherHero, .weatherHourly, .weatherDaily: true
        default: false
        }
    }

    public var usesMedia: Bool { self == .media || self == .mediaPlayer }

    public var isPerformance: Bool { rawValue.hasPrefix("performance.") }

    public var sizes: [WidgetSize] {
        if let card = overviewCard { return Self.overviewSizes(card) }
        let p = PerformancePageGeometry.self
        let w = DashboardGeometry.width
        switch self {
        case .performanceCPU, .performanceGPU:
            return [.flexible(p.heroWidths(hasBattery: true).min()!, p.heroWidths(hasBattery: false).max()!, p.heroHeight)]
        case .performanceStorage, .performanceMemory:
            return [.flexible(p.sideWidths(hasBattery: true).min()!, p.sideWidths(hasBattery: false).max()!, p.bottomHeight)]
        case .performanceNetwork: return [.fixed(p.networkWidth, p.bottomHeight)]
        case .performanceBattery: return [.fixed(p.batteryWidth, DashboardGeometry.height)]
        case .weatherHero: return [.fixed(w, WeatherPageGeometry.heroHeight)]
        case .weatherHourly: return [.fixed(w, WeatherPageGeometry.hourlyHeight)]
        case .weatherDaily: return [.fixed(w, WeatherPageGeometry.dailyHeight)]
        case .mediaPlayer: return [.fixed(w, DashboardGeometry.height)]
        case .weather, .user, .clock, .calendar, .resources, .media: return []
        }
    }

    /// Kleinste Groesse nach Flaeche (Mindestbreite x Hoehe) - so kommt ein
    /// neues Widget aus Nexus auf die Seite.
    public var smallestSize: WidgetSize {
        sizes.min { $0.minWidth * $0.height < $1.minWidth * $1.height }!
    }

    public func allows(width: Double, height: Double) -> Bool {
        sizes.contains { $0.allows(width: width, height: height) }
    }

    /// Karten der Uebersicht: jede Breite von der kleinsten ihrer Plaetze bis
    /// zur ganzen Seite - eine Reihe ohne flexible Karte wurde vor 0.2 im
    /// Verhaeltnis gestreckt, eine Spaltenkarte allein fuellte die Seite. Die
    /// Hoehen sind die ihrer Plaetze: obere Reihe 130, untere 250, eine Reihe
    /// allein oder die Spalte 392.
    static func overviewSizes(_ card: DashboardCardKind) -> [WidgetSize] {
        let g = DashboardGeometry.self
        let bottomHeight = g.height - g.topHeight - g.spacing
        var minimumByHeight: [Double: Double] = [:]
        for zone in card.zones {
            let minimum = card.width(in: zone).minimum
            let heights: [Double] = switch zone {
            case .top: [g.topHeight, g.height]
            case .bottom: [bottomHeight, g.height]
            case .side: [g.height]
            }
            for height in heights {
                minimumByHeight[height] = min(minimumByHeight[height] ?? minimum, minimum)
            }
        }
        return minimumByHeight.keys.sorted().map { .flexible(minimumByHeight[$0]!, g.width, $0) }
    }
}

/// Masse der Seite Leistung, Caelestias Werte x 0,858 (vor 0.2 fest in
/// PerformanceView). Links CPU und GPU ueber Speicher, Netzwerk,
/// Arbeitsspeicher, rechts der Akku - ohne Akku wird links alles breiter.
public enum PerformancePageGeometry {
    public static let batteryWidth: Double = 129   // 150 x 0,858
    public static let networkWidth: Double = 335   // 390 x 0,858
    public static let bottomHeight: Double = 189   // 220 x 0,858
    public static var heroHeight: Double { DashboardGeometry.height - bottomHeight - DashboardGeometry.spacing }

    public static func leftWidth(hasBattery: Bool) -> Double {
        hasBattery ? DashboardGeometry.width - DashboardGeometry.spacing - batteryWidth : DashboardGeometry.width
    }

    /// CPU und GPU nebeneinander.
    public static func heroWidths(hasBattery: Bool) -> [Double] {
        split(leftWidth(hasBattery: hasBattery) - DashboardGeometry.spacing)
    }

    /// Speicher und Arbeitsspeicher links und rechts vom Netzwerk.
    public static func sideWidths(hasBattery: Bool) -> [Double] {
        split(leftWidth(hasBattery: hasBattery) - networkWidth - 2 * DashboardGeometry.spacing)
    }

    /// Genau halbiert. Anders als `DashboardGeometry.widths` (ganze Punkte,
    /// Rest an die letzte Karte): eine Vorlage darf einen Halbpunkt haben, das
    /// Runden verschob eine Karte im Bildvergleich um ein Pixel (gemessen).
    /// Gezogene Rahmen bleiben trotzdem ganze Punkte (`WidgetFrame.rounded()`).
    static func split(_ total: Double) -> [Double] {
        [total / 2, total / 2]
    }
}

/// Masse der Seite Wetter (vor 0.2 fest in WeatherTab).
public enum WeatherPageGeometry {
    public static let heroHeight: Double = 116
    public static let hourlyHeight: Double = 108
    public static let spacing: Double = 12
    public static var dailyHeight: Double { DashboardGeometry.height - heroHeight - hourlyHeight - 2 * spacing }
}
