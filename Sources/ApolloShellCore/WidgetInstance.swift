import Foundation

/// Frame of a widget on the page, in reference points from the top left
/// corner (page 839 x 392, `DashboardGeometry`). Stored as whole points.
public struct WidgetFrame: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: DashboardRect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    /// Dragging yields fractions; storage is in whole points.
    public func rounded() -> WidgetFrame {
        WidgetFrame(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }
}

/// Options of a widget. Each kind reads only its own field (the clock's
/// `clock`, ...), the rest stay `nil` and don't appear in the file.
/// If the field for its own kind is missing, its defaults apply (`?? .init()` in
/// the view).
public struct WidgetOptions: Codable, Equatable, Sendable {
    public var weather: DashboardWeatherOptions?
    public var user: DashboardUserOptions?
    public var clock: DashboardClockOptions?
    public var calendar: DashboardCalendarOptions?
    public var resources: DashboardResourcesOptions?
    public var media: DashboardMediaOptions?
    /// Locations of the weather widgets, one list per widget.
    public var places: WeatherFavorites?

    public init(weather: DashboardWeatherOptions? = nil, user: DashboardUserOptions? = nil,
                clock: DashboardClockOptions? = nil, calendar: DashboardCalendarOptions? = nil,
                resources: DashboardResourcesOptions? = nil, media: DashboardMediaOptions? = nil,
                places: WeatherFavorites? = nil) {
        self.weather = weather
        self.user = user
        self.clock = clock
        self.calendar = calendar
        self.resources = resources
        self.media = media
        self.places = places
    }

    /// Defaults of a kind. Weather widgets get `places` (during migration, the
    /// favorites from weather.json).
    public static func defaults(for kind: WidgetKind, places: WeatherFavorites = .empty) -> WidgetOptions {
        var options = WidgetOptions()
        switch kind {
        case .weather:
            options.weather = DashboardWeatherOptions()
            options.places = places
        case .weatherHero, .weatherHourly, .weatherDaily: options.places = places
        case .user: options.user = DashboardUserOptions()
        case .clock: options.clock = DashboardClockOptions()
        case .calendar: options.calendar = DashboardCalendarOptions()
        case .resources: options.resources = DashboardResourcesOptions()
        case .media: options.media = DashboardMediaOptions()
        case .performanceCPU, .performanceGPU, .performanceStorage, .performanceNetwork,
             .performanceMemory, .performanceBattery, .mediaPlayer:
            break
        }
        return options
    }

    private enum CodingKeys: String, CodingKey { case weather, user, clock, calendar, resources, media, places }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weather = c.lenient(.weather)
        user = c.lenient(.user)
        clock = c.lenient(.clock)
        calendar = c.lenient(.calendar)
        resources = c.lenient(.resources)
        media = c.lenient(.media)
        places = c.lenient(.places)
    }
}

/// A widget on a page. The same kind may occur more than once, each
/// with its own options (two clocks, two weather widgets).
public struct WidgetInstance: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: WidgetKind
    public var frame: WidgetFrame
    public var options: WidgetOptions

    public init(id: UUID = UUID(), kind: WidgetKind, frame: WidgetFrame, options: WidgetOptions? = nil) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.options = options ?? .defaults(for: kind)
    }

    private enum CodingKeys: String, CodingKey { case id, kind, frame, options }

    /// Unknown kind or missing frame: error - the page then skips the
    /// widget. Missing identifier: a new one; broken options: defaults.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let raw: String = c.lenient(.kind), let kind = WidgetKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown widget")
        }
        guard let frame: WidgetFrame = c.lenient(.frame) else {
            throw DecodingError.dataCorruptedError(forKey: .frame, in: c, debugDescription: "frame missing")
        }
        self.init(id: c.lenient(.id) ?? UUID(), kind: kind, frame: frame, options: c.lenient(.options))
    }
}
