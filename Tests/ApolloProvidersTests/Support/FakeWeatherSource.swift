import Foundation
import ApolloRuntime
import ApolloShellCore
@testable import ApolloProviders

@MainActor
final class FakeWeatherSource: WeatherSource {
    static let start = Date(timeIntervalSince1970: 1_790_236_800)

    let clock: ManualRuntimeClock
    var fetches: [(WeatherProviderID, WeatherPlace)] = []
    var pending: [@MainActor (WeatherReport?) -> Void] = []
    var answer: WeatherReport?
    var answersImmediately = true
    var searches: [String] = []
    var searchAnswer: [GeocodingPlace]? = [GeocodingPlace(id: 1, name: "Chur", latitude: 46.85, longitude: 9.53, admin1: "Graubünden", country: "Schweiz")]

    init(clock: ManualRuntimeClock) {
        self.clock = clock
        answer = Self.report(at: Self.start)
    }

    var now: Date { Self.start.addingTimeInterval(clock.now) }

    func fetch(_ provider: WeatherProviderID, for place: WeatherPlace, _ completion: @escaping @MainActor (WeatherReport?) -> Void) {
        fetches.append((provider, place))
        if answersImmediately { completion(answer) } else { pending.append(completion) }
    }

    func finish() {
        let waiting = pending
        pending.removeAll()
        for completion in waiting { completion(answer) }
    }

    func search(_ query: String, _ completion: @escaping @MainActor ([GeocodingPlace]?) -> Void) {
        searches.append(query)
        completion(searchAnswer)
    }

    static func report(at now: Date) -> WeatherReport {
        let zone = TimeZone(identifier: "Europe/Zurich")!
        let hours = (0..<48).map { HourForecast(time: now.addingTimeInterval(Double($0) * 3600), temperature: 10 + Double($0 % 5), code: 2, precipitationProbability: $0 * 5, isDay: true) }
        let days = (0..<8).map { DayForecast(date: Calendar.current.startOfDay(for: now).addingTimeInterval(Double($0) * 86400), code: 61, maxTemperature: 18, minTemperature: 7, sunrise: nil, sunset: nil, precipitationProbability: 40) }
        return WeatherReport(current: CurrentWeather(time: now, temperature: 14, apparentTemperature: .nan, humidity: 71, code: 2, windSpeed: 12, isDay: true), hours: hours, days: days, timeZone: zone)
    }
}
