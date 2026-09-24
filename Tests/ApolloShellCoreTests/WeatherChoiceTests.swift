import Foundation
import ApolloShellCore
import Testing

@Suite("Wetter: Favoriten und erneutes Versuchen")
struct WeatherChoiceTests {
    static let berlin = WeatherLocation(name: "Berlin", latitude: 52.52, longitude: 13.405)
    static let vienna = WeatherLocation(name: "Wien", latitude: 48.2082, longitude: 16.3738)
    static let oslo = WeatherLocation(name: "Oslo", latitude: 59.9139, longitude: 10.7522)

    @Test("frisch: keine Favoriten, kein gewaehlter Ort")
    func empty() {
        #expect(WeatherFavorites.empty.locations.isEmpty)
        #expect(WeatherFavorites.empty.selected == nil)
    }

    @Test("Hinzufuegen: erster Favorit wird gleich gewaehlt, doppelte Koordinaten fallen weg")
    func addNoDuplicate() {
        var favorites = WeatherFavorites.empty
        let addedBerlin = favorites.add(Self.berlin)
        #expect(addedBerlin)
        #expect(favorites.locations == [Self.berlin])
        #expect(favorites.selected == Self.berlin)

        let addedVienna = favorites.add(Self.vienna)
        #expect(addedVienna)
        #expect(favorites.locations == [Self.berlin, Self.vienna])
        // weiterhin der erste gewaehlt
        #expect(favorites.selected == Self.berlin)

        // dieselben Koordinaten, anderer Name: kein zweiter Eintrag
        let renamed = WeatherLocation(name: "Berlin Mitte", latitude: 52.52, longitude: 13.405)
        let addedDuplicate = favorites.add(renamed)
        #expect(!addedDuplicate)
        #expect(favorites.locations.count == 2)
    }

    @Test("Entfernen des gewaehlten Orts: kein Ort mehr gewaehlt")
    func removeSelected() {
        var favorites = WeatherFavorites.empty
        favorites.add(Self.berlin)
        favorites.add(Self.vienna)
        favorites.select(id: Self.vienna.id)
        favorites.remove(id: Self.vienna.id)
        #expect(favorites.locations == [Self.berlin])
        #expect(favorites.selected == nil)
    }

    @Test("Entfernen eines anderen Favoriten laesst die Auswahl stehen")
    func removeOther() {
        var favorites = WeatherFavorites.empty
        favorites.add(Self.berlin)
        favorites.add(Self.vienna)
        favorites.remove(id: Self.vienna.id)
        #expect(favorites.locations == [Self.berlin])
        #expect(favorites.selected == Self.berlin)
    }

    @Test("Umsortieren per Drag")
    func move() {
        var favorites = WeatherFavorites.empty
        favorites.add(Self.berlin)
        favorites.add(Self.vienna)
        favorites.add(Self.oslo)
        favorites.move(fromOffsets: [2], toOffset: 0)
        #expect(favorites.locations.map(\.name) == ["Oslo", "Berlin", "Wien"])
    }

    @Test("Waehlen geht nur bei einem vorhandenen Favoriten")
    func selectUnknown() {
        var favorites = WeatherFavorites.empty
        favorites.add(Self.berlin)
        let unknownID = UUID()
        favorites.select(id: unknownID)
        #expect(favorites.selected == Self.berlin)
    }

    @Test("gewaehlte Favoriten ueberleben den Weg durch weather.json")
    func roundTrip() {
        var favorites = WeatherFavorites.empty
        favorites.add(Self.berlin)
        favorites.add(Self.vienna)
        favorites.select(id: Self.vienna.id)
        let loaded = WeatherFavorites.load(from: favorites.fileData())
        #expect(loaded.locations == favorites.locations)
        #expect(loaded.selectedID == favorites.selectedID)
    }

    @Test("Migration: alte weather.json (ein Ort) wird zum ersten Favoriten")
    func migration() {
        let data = Data(#"{"name":"Oslo","latitude":59.9139,"longitude":10.7522}"#.utf8)
        let favorites = WeatherFavorites.load(from: data)
        #expect(favorites.locations.map(\.name) == ["Oslo"])
        #expect(favorites.selected?.name == "Oslo")
    }

    @Test("Kaputt oder fehlend: keine Favoriten")
    func invalid() {
        #expect(WeatherFavorites.load(from: nil) == .empty)
        #expect(WeatherFavorites.load(from: Data("{".utf8)) == .empty)
        #expect(WeatherFavorites.load(from: Data(#"{"name":"X","latitude":95,"longitude":9}"#.utf8)) == .empty)
    }

    @Test("nach Fehlschlag bald nochmal, dann seltener")
    func retry() {
        #expect(WeatherRefresh.retryDelay(afterFailures: 1) == 10)
        #expect(WeatherRefresh.retryDelay(afterFailures: 2) == 30)
        #expect(WeatherRefresh.retryDelay(afterFailures: 3) == 60)
        #expect(WeatherRefresh.retryDelay(afterFailures: 4) == 300)
        #expect(WeatherRefresh.retryDelay(afterFailures: 40) == 300)
    }
}
