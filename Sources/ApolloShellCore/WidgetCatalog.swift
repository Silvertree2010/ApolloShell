import Foundation

// The catalogue of the widgets for the bento dashboard (0.2, see
// design/2026-09-18-bento-dashboard.md). Every widget is described here once:
// id, name, symbol, home, allowed sizes. The sizes are exactly the ones the
// dashboard could draw before 0.2.

/// Where a widget is at home. Outside its home only as an advanced option in
/// Nexus, and not optimised there.
public enum WidgetSurface: String, Codable, CaseIterable, Sendable {
    case dashboard, controlCentre
}

/// One allowed size in reference points (a page of 839 x 392). A fixed width:
/// `minWidth == maxWidth`. The height is always fixed.
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

/// How a widget shows itself (`WidgetKind.displays`, `WidgetOptions.display`).
/// The raw value stands in settings.json - never rename it.
public enum WidgetDisplay: String, Codable, CaseIterable, Sendable {
    case standard, minimal, analog, today, bars, cover, graph, gauge, bar, numbers, ring, list
}

/// All widgets. The raw value stands in settings.json - never rename it. The
/// six cards of the overview keep the ids of `DashboardCardKind`.
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
        // The same raw values, the test `cardsMap` pins that down.
        self = WidgetKind(rawValue: card.rawValue)!
    }

    /// The card from before 0.2, when the widget is one.
    public var overviewCard: DashboardCardKind? { DashboardCardKind(rawValue: rawValue) }

    public var title: String {
        if let card = overviewCard { return card.title }
        return switch self {
        case .performanceCPU: "CPU"
        case .performanceGPU: "GPU"
        case .performanceStorage: String(localized: "Storage")
        case .performanceNetwork: String(localized: "Network")
        case .performanceMemory: String(localized: "Memory")
        case .performanceBattery: String(localized: "Battery")
        case .weatherHero: String(localized: "Weather overview")
        case .weatherHourly: String(localized: "Hourly")
        case .weatherDaily: String(localized: "Next days")
        case .mediaPlayer: String(localized: "Play")
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

    /// All of today's widgets belong in the dashboard; the control centre gets
    /// its own only with the editor for all surfaces.
    public var home: WidgetSurface { .dashboard }

    /// Weather widgets carry their own list of places (`WidgetOptions.places`).
    public var usesPlaces: Bool {
        switch self {
        case .weather, .weatherHero, .weatherHourly, .weatherDaily: true
        default: false
        }
    }

    public var usesMedia: Bool { self == .media || self == .mediaPlayer }

    public var isPerformance: Bool { rawValue.hasPrefix("performance.") }

    /// The page widgets got sizes of their own on 09/23: besides the one
    /// from their page, the heights of the overview (130, 250, 392), so that
    /// they fit into its rows. At most one size per height - resizing picks
    /// the size by the nearest height (`BentoGeometry.snapResize`).
    public var sizes: [WidgetSize] {
        if let card = overviewCard { return Self.overviewSizes(card) }
        let p = PerformancePageGeometry.self
        let w = DashboardGeometry.width
        let h = DashboardGeometry.height
        let top = DashboardGeometry.topHeight
        let bottom = h - top - DashboardGeometry.spacing
        switch self {
        case .performanceCPU, .performanceGPU:
            return [.flexible(220, w, top),
                    .flexible(p.heroWidths(hasBattery: true).min()!, w, p.heroHeight),
                    .flexible(250, w, bottom),
                    .flexible(250, w, h)]
        case .performanceStorage, .performanceMemory:
            return [.flexible(200, w, top),
                    .flexible(p.sideWidths(hasBattery: true).min()!, 420, p.bottomHeight),
                    .flexible(p.sideWidths(hasBattery: true).min()!, 420, bottom),
                    .flexible(p.sideWidths(hasBattery: true).min()!, 420, h)]
        case .performanceNetwork:
            return [.flexible(230, w, top),
                    .flexible(p.networkWidth, w, p.bottomHeight),
                    .flexible(300, w, bottom),
                    .flexible(300, w, h)]
        case .performanceBattery:
            return [.flexible(p.batteryWidth, 420, top),
                    .flexible(p.batteryWidth, 420, bottom),
                    .flexible(p.batteryWidth, 420, h)]
        case .weatherHero:
            return [.flexible(500, w, WeatherPageGeometry.heroHeight),
                    .flexible(275, w, bottom),
                    .flexible(275, w, h)]
        case .weatherHourly:
            return [.flexible(300, w, WeatherPageGeometry.hourlyHeight),
                    .flexible(300, w, bottom)]
        case .weatherDaily:
            return [.flexible(300, w, WeatherPageGeometry.dailyHeight),
                    .flexible(275, w, bottom),
                    .flexible(200, w, h)]
        case .mediaPlayer:
            return [.flexible(413, w, bottom), .flexible(413, w, h)]
        case .weather, .user, .clock, .calendar, .resources, .media: return []
        }
    }

    /// The ways a widget can show itself, chosen in its options. The first one
    /// is the default, the look from before 09/23.
    public var displays: [WidgetDisplay] {
        switch self {
        case .weather, .user, .weatherHero: [.standard, .minimal]
        case .clock: [.standard, .analog]
        case .calendar: [.standard, .today]
        case .resources: [.standard, .bars]
        case .media, .mediaPlayer: [.standard, .cover]
        case .performanceCPU, .performanceGPU: [.standard, .graph, .gauge]
        case .performanceStorage, .performanceMemory: [.standard, .bar]
        case .performanceNetwork: [.standard, .numbers]
        case .performanceBattery: [.standard, .ring]
        case .weatherHourly: [.standard, .graph]
        case .weatherDaily: [.standard, .list]
        }
    }

    /// The smallest size by area (minimum width x height) - that is how a new
    /// widget out of Nexus lands on the page.
    public var smallestSize: WidgetSize {
        sizes.min { $0.minWidth * $0.height < $1.minWidth * $1.height }!
    }

    public func allows(width: Double, height: Double) -> Bool {
        sizes.contains { $0.allows(width: width, height: height) }
    }

    /// The cards of the overview: every width from the smallest of their places
    /// up to the whole page - a row without a flexible card was stretched in
    /// proportion before 0.2, and a column card on its own filled the page. The
    /// heights are those of their places: the top row 130, the bottom one 250,
    /// a row on its own or the column 392.
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

/// The measurements of the performance page, Caelestia's values x 0.858
/// (fixed in PerformanceView before 0.2). On the left CPU and GPU above
/// storage, network and memory, on the right the battery.
public enum PerformancePageGeometry {
    public static let batteryWidth: Double = 129   // 150 x 0.858
    public static let networkWidth: Double = 335   // 390 x 0.858
    public static let bottomHeight: Double = 189   // 220 x 0.858
    public static var heroHeight: Double { DashboardGeometry.height - bottomHeight - DashboardGeometry.spacing }

    public static func leftWidth(hasBattery: Bool) -> Double {
        hasBattery ? DashboardGeometry.width - DashboardGeometry.spacing - batteryWidth : DashboardGeometry.width
    }

    /// CPU and GPU side by side.
    public static func heroWidths(hasBattery: Bool) -> [Double] {
        split(leftWidth(hasBattery: hasBattery) - DashboardGeometry.spacing)
    }

    /// Storage and memory to the left and the right of the network.
    public static func sideWidths(hasBattery: Bool) -> [Double] {
        split(leftWidth(hasBattery: hasBattery) - networkWidth - 2 * DashboardGeometry.spacing)
    }

    /// Exactly halved. Unlike `DashboardGeometry.widths` (whole points, the
    /// rest to the last card): a template may have a half point, and the
    /// rounding shifted a card by one pixel in the image comparison (measured).
    /// Dragged frames still stay whole points (`WidgetFrame.rounded()`).
    static func split(_ total: Double) -> [Double] {
        [total / 2, total / 2]
    }
}

/// The measurements of the weather page (fixed in WeatherTab before 0.2).
public enum WeatherPageGeometry {
    public static let heroHeight: Double = 116
    public static let hourlyHeight: Double = 108
    public static let spacing: Double = 12
    public static var dailyHeight: Double { DashboardGeometry.height - heroHeight - hourlyHeight - 2 * spacing }
}
