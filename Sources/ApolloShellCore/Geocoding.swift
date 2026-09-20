import Foundation

/// One hit of the place search of Open-Meteo.
public struct GeocodingPlace: Equatable, Sendable, Identifiable {
    /// The GeoNames id; with places of the same name (Springfield IL,
    /// Springfield MO) the only sure way to tell them apart.
    public let id: Int
    public let name: String
    public let latitude: Double
    public let longitude: Double
    /// The region, "Land Berlin" for instance.
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

    /// The second line: "Land Berlin, Germany". Empty parts fall away.
    public var detail: String {
        [admin1, country]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// For weather.json.
    public var location: WeatherLocation {
        WeatherLocation(name: name, latitude: latitude, longitude: longitude)
    }
}

/// The place search through https://geocoding-api.open-meteo.com (no key, the
/// same source as the weather).
public enum OpenMeteoGeocoding {
    /// How many hits, and in which language the names come.
    public static let count = 5
    public static let language = "de"
    /// Below two characters the interface delivers nothing usable (documented:
    /// 1 character = an empty list, 2 = exact hits).
    public static let minimumQueryLength = 2
    /// Wait this long after the last key press before searching - otherwise
    /// four requests would go out for "Oslo".
    public static let debounce: Duration = .milliseconds(400)

    /// `nil` when the search text is too short - then do not ask at all.
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

    /// When the interface finds nothing, `results` is missing entirely
    /// (measured 14.09.: only `generationtime_ms`) - that is an empty list, not
    /// an error. Hits without a name or with coordinates off the Earth fall away.
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
            // Without an id: the position in the answer, negative, so that it
            // never coincides with a real GeoNames id.
            return GeocodingPlace(id: r.id ?? -(index + 1), name: name, latitude: latitude,
                                  longitude: longitude, admin1: r.admin1, country: r.country)
        }
    }
}

extension WeatherLocation {
    /// "47,01° N, 9,50° E" in German, "47.01° N, 9.50° E" in English: the
    /// decimal separator comes out of the locale, the direction is a
    /// translation key.
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
