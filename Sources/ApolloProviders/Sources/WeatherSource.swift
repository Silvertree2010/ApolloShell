import Foundation
import ApolloShellCore

public struct WeatherPlace: Equatable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double

    public init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    public var location: WeatherLocation {
        WeatherLocation(name: name, latitude: latitude, longitude: longitude)
    }
}

@MainActor
public protocol WeatherSource: AnyObject {
    var now: Date { get }
    func fetch(_ provider: WeatherProviderID, for place: WeatherPlace, _ completion: @escaping @MainActor (WeatherReport?) -> Void)
    func search(_ query: String, _ completion: @escaping @MainActor ([GeocodingPlace]?) -> Void)
}
