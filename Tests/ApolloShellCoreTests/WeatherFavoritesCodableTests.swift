import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Weather places as part of settings.json (0.2)")
struct WeatherFavoritesCodableTests {
    private let zurich = WeatherLocation(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                         name: "Zürich", latitude: 47.37, longitude: 8.54)
    private let chur = WeatherLocation(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                                       name: "Chur", latitude: 46.85, longitude: 9.53)

    @Test("Round trip: same places, same selected one")
    func roundTrip() throws {
        let favorites = WeatherFavorites(locations: [zurich, chur], selectedID: chur.id)
        let data = try JSONEncoder().encode(favorites)
        #expect(try JSONDecoder().decode(WeatherFavorites.self, from: data) == favorites)
    }

    @Test("Same format as weather.json")
    func sameShapeAsFile() throws {
        let favorites = WeatherFavorites(locations: [zurich], selectedID: zurich.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        #expect(try encoder.encode(favorites) == favorites.fileData())
    }

    @Test("Lenient: a place off the Earth falls away, missing selection = the first")
    func lenient() throws {
        let json = #"{"favorites":[{"name":"X","latitude":95,"longitude":0},{"id":"00000000-0000-0000-0000-000000000002","name":"Chur","latitude":46.85,"longitude":9.53}]}"#
        let favorites = try JSONDecoder().decode(WeatherFavorites.self, from: Data(json.utf8))
        #expect(favorites.locations.map(\.name) == ["Chur"])
        #expect(favorites.selectedID == chur.id)
    }
}
