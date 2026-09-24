import Foundation
import ApolloProviders
import ApolloShellCore
import os

@MainActor
final class SystemWeatherSource: WeatherSource {
    private static let userAgent = WeatherUserAgent.value(version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)

    private let log = Logger(category: "weather")
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    var now: Date { Date() }

    func fetch(_ provider: WeatherProviderID, for place: WeatherPlace, _ completion: @escaping @MainActor (WeatherReport?) -> Void) {
        let weather = provider.provider()
        let requests = weather.requests(for: place.location, now: Date()).map { ($0.optional, $0.urlRequest(userAgent: Self.userAgent)) }
        let session = session
        let log = log
        Task.detached {
            var report: WeatherReport?
            do {
                var bodies: [Data?] = []
                for (optional, request) in requests {
                    do {
                        bodies.append(try await Self.load(request, session: session))
                    } catch {
                        guard optional else { throw error }
                        bodies.append(nil)
                    }
                }
                report = try weather.decode(bodies, now: Date())
            } catch {
                let nsError = error as NSError
                log.error("weather not fetched: \(provider.rawValue, privacy: .public) \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            }
            let result = report
            await MainActor.run { completion(result) }
        }
    }

    func search(_ query: String, _ completion: @escaping @MainActor ([GeocodingPlace]?) -> Void) {
        guard let url = OpenMeteoGeocoding.url(for: query) else { return completion([]) }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let session = session
        Task.detached {
            let places = try? OpenMeteoGeocoding.decode(await Self.load(request, session: session))
            await MainActor.run { completion(places) }
        }
    }

    nonisolated private static func load(_ request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 203 else { throw URLError(.badServerResponse) }
        return data
    }
}
