import Foundation

public struct GeocodingPlace: Equatable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let admin1: String?
    public let country: String?

    public init(id: Int, name: String, latitude: Double, longitude: Double, admin1: String?, country: String?) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.admin1 = admin1
        self.country = country
    }

    public var detail: String {
        [admin1, country]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    public var location: WeatherLocation {
        WeatherLocation(name: name, latitude: latitude, longitude: longitude)
    }
}

public enum OpenMeteoGeocoding {
    public static let count = 5
    public static let language = "de"
    public static let minimumQueryLength = 2
    public static let debounce: Duration = .milliseconds(400)

    public static func url(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumQueryLength else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "geocoding-api.open-meteo.com"
        components.path = "/v1/search"
        components.queryItems = [
            URLQueryItem(name: "name", value: trimmed),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components.url
    }

    public static func decode(_ data: Data) throws -> [GeocodingPlace] {
        struct Raw: Decodable {
            struct Result: Decodable {
                let id: Int?
                let name: String?
                let latitude: Double?
                let longitude: Double?
                let admin1: String?
                let country: String?
            }
            let results: [Result]?
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        return (raw.results ?? []).enumerated().compactMap { index, r in
            guard let name = r.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
                  let latitude = r.latitude, let longitude = r.longitude,
                  (-90...90).contains(latitude), (-180...180).contains(longitude)
            else { return nil }
            return GeocodingPlace(id: r.id ?? -(index + 1), name: name, latitude: latitude,
                                  longitude: longitude, admin1: r.admin1, country: r.country)
        }
    }
}

extension WeatherLocation {
    public var coordinateText: String { coordinateText(locale: .current) }

    public func coordinateText(locale: Locale) -> String {
        func part(_ value: Double, _ positive: String, _ negative: String) -> String {
            let text = String(format: "%.2f", abs(value))
                .replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".")
            return "\(text)° \(value < 0 ? negative : positive)"
        }
        let north = String(localized: "N"), south = String(localized: "S")
        let east = String(localized: "E"), west = String(localized: "W")
        return part(latitude, north, south) + ", " + part(longitude, east, west)
    }
}
