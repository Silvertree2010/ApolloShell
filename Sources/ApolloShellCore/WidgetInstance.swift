import Foundation

/// Rahmen eines Widgets auf der Seite, in Referenzpunkten ab der Ecke oben
/// links (Seite 839 x 392, `DashboardGeometry`). Gespeichert als ganze Punkte.
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

    /// Ziehen liefert Bruchteile; gespeichert wird in ganzen Punkten.
    public func rounded() -> WidgetFrame {
        WidgetFrame(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }
}

/// Optionen eines Widgets. Jede Art liest nur ihr eigenes Feld (die Uhr
/// `clock`, ...), die uebrigen bleiben `nil` und stehen nicht in der Datei.
/// Fehlt das Feld der eigenen Art, gelten deren Vorgaben (`?? .init()` in
/// der Ansicht).
public struct WidgetOptions: Codable, Equatable, Sendable {
    public var weather: DashboardWeatherOptions?
    public var user: DashboardUserOptions?
    public var clock: DashboardClockOptions?
    public var calendar: DashboardCalendarOptions?
    public var resources: DashboardResourcesOptions?
    public var media: DashboardMediaOptions?
    /// Orte der Wetter-Widgets, je Widget eine eigene Liste.
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

    /// Vorgaben einer Art. Wetter-Widgets bekommen `places` (beim Umzug die
    /// Favoriten aus weather.json).
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

/// Ein Widget auf einer Seite. Dieselbe Art darf mehrfach vorkommen, jede
/// mit eigenen Optionen (zwei Uhren, zwei Wetter).
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

    /// Unbekannte Art oder fehlender Rahmen: Fehler - die Seite uebergeht das
    /// Widget dann. Fehlende Kennung: eine neue; kaputte Optionen: Vorgaben.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let raw: String = c.lenient(.kind), let kind = WidgetKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unbekanntes Widget")
        }
        guard let frame: WidgetFrame = c.lenient(.frame) else {
            throw DecodingError.dataCorruptedError(forKey: .frame, in: c, debugDescription: "Rahmen fehlt")
        }
        self.init(id: c.lenient(.id) ?? UUID(), kind: kind, frame: frame, options: c.lenient(.options))
    }
}
