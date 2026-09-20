import Foundation
import ApolloShellCore
import Testing

@Suite("Weather: favorites and retrying")
struct WeatherChoiceTests {
    static let berlin = WeatherLocation(name: "Berlin", latitude: 52.52, longitude: 13.405)
    static let vienna = WeatherLocation(name: "Wien", latitude: 48.2082, longitude: 16.3738)
    static let oslo = WeatherLocation(name: "Oslo", latitude: 59.9139, longitude: 10.7522)

    @Test("fresh: no favorites, no selected location")
    func empty() {
        #expect(WeatherFavorites.empty.locations.isEmpty)
        #expect(WeatherFavorites.empty.selected == nil)
    }

    @Test("adding: first favorite is selected right away, duplicate coordinates are dropped")
    func addNoDuplicate() {
        var favorites = WeatherFavorites.empty
        let addedBerlin = favorites.add(Self.berlin)
        #expect(addedBerlin)
        #expect(favorites.locations == [Self.berlin])
        #expect(favorites.selected == Self.berlin)

        let addedVienna = favorites.add(Self.vienna)
        #expect(addedVienna)
        #expect(favorites.locations == [Self.berlin, Self.vienna])
        // still the first one selected
        #expect(favorites.selected == Self.berlin)

        // same coordinates, different name: no second entry
        let renamed = WeatherLocation(name: "Berlin Mitte", latitude: 52.52, longitude: 13.405)
        let addedDuplicate = favorites.add(renamed)
        #expect(!addedDuplicate)
        #expect(favorites.locations.count == 2)
    }

    @Test("removing the selected location: no location selected anymore")
    func removeSelected() {
        var favorites = WeatherFavorites.empty
        favorites.add(Self.berlin)
        favorites.add(Self.vienna)
        favorites.select(id: Self.vienna.id)
        favorites.remove(id: Self.vienna.id)
        #expect(favorites.locations == [Self.berlin])
        #expect(favorites.selected == nil)
    }

    @Test("removing a different favorite leaves the selection in place")
    func removeOther() {
        var favorites = WeatherFavorites.empty
        favorites.add(Self.berlin)
        favorites.add(Self.vienna)
        favorites.remove(id: Self.vienna.id)
        #expect(favorites.locations == [Self.berlin])
        #expect(favorites.selected == Self.berlin)
    }

    @Test("reordering via drag")
    func move() {
        var favorites = WeatherFavorites.empty
        favorites.add(Self.berlin)
        favorites.add(Self.vienna)
        favorites.add(Self.oslo)
        favorites.move(fromOffsets: [2], toOffset: 0)
        #expect(favorites.locations.map(\.name) == ["Oslo", "Berlin", "Wien"])
    }

    @Test("selecting only works for an existing favorite")
    func selectUnknown() {
        var favorites = WeatherFavorites.empty
        favorites.add(Self.berlin)
        let unknownID = UUID()
        favorites.select(id: unknownID)
        #expect(favorites.selected == Self.berlin)
    }

    @Test("the selected favorite survives the round trip through weather.json")
    func roundTrip() {
        var favorites = WeatherFavorites.empty
        favorites.add(Self.berlin)
        favorites.add(Self.vienna)
        favorites.select(id: Self.vienna.id)
        let loaded = WeatherFavorites.load(from: favorites.fileData())
        #expect(loaded.locations == favorites.locations)
        #expect(loaded.selectedID == favorites.selectedID)
    }

    @Test("migration: old weather.json (one location) becomes the first favorite")
    func migration() {
        let data = Data(#"{"name":"Oslo","latitude":59.9139,"longitude":10.7522}"#.utf8)
        let favorites = WeatherFavorites.load(from: data)
        #expect(favorites.locations.map(\.name) == ["Oslo"])
        #expect(favorites.selected?.name == "Oslo")
    }

    @Test("broken or missing: no favorites")
    func invalid() {
        #expect(WeatherFavorites.load(from: nil) == .empty)
        #expect(WeatherFavorites.load(from: Data("{".utf8)) == .empty)
        #expect(WeatherFavorites.load(from: Data(#"{"name":"X","latitude":95,"longitude":9}"#.utf8)) == .empty)
    }

    @Test("soon again after a failure, then less often")
    func retry() {
        #expect(WeatherRefresh.retryDelay(afterFailures: 1) == 10)
        #expect(WeatherRefresh.retryDelay(afterFailures: 2) == 30)
        #expect(WeatherRefresh.retryDelay(afterFailures: 3) == 60)
        #expect(WeatherRefresh.retryDelay(afterFailures: 4) == 300)
        #expect(WeatherRefresh.retryDelay(afterFailures: 40) == 300)
    }
}
