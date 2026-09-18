import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Widget auf einer Seite: Rahmen, Optionen, nachsichtiges Lesen")
struct WidgetInstanceTests {
    private func decode(_ json: String) -> WidgetInstance? {
        try? JSONDecoder().decode(WidgetInstance.self, from: Data(json.utf8))
    }

    @Test("Vorgaben je Art: nur das eigene Feld, Wetter mit Orten")
    func defaults() {
        let place = WeatherLocation(name: "Chur", latitude: 46.85, longitude: 9.53)
        let places = WeatherFavorites(locations: [place], selectedID: place.id)
        let weather = WidgetOptions.defaults(for: .weather, places: places)
        #expect(weather.weather == DashboardWeatherOptions())
        #expect(weather.places == places)
        #expect(weather.clock == nil)
        #expect(WidgetOptions.defaults(for: .weatherDaily, places: places).places == places)
        #expect(WidgetOptions.defaults(for: .clock).clock == DashboardClockOptions())
        #expect(WidgetOptions.defaults(for: .performanceCPU) == WidgetOptions())
    }

    @Test("Hin und zurueck")
    func roundTrip() throws {
        let widget = WidgetInstance(kind: .clock, frame: WidgetFrame(x: 0, y: 142, width: 110, height: 250),
                                    options: WidgetOptions(clock: DashboardClockOptions(timeZone: "Asia/Tokyo")))
        let data = try JSONEncoder().encode(widget)
        #expect(try JSONDecoder().decode(WidgetInstance.self, from: data) == widget)
        #expect(!String(decoding: data, as: UTF8.self).contains("\"weather\""))
    }

    @Test("Unbekannte Art oder fehlender Rahmen: nicht lesbar")
    func rejects() {
        #expect(decode(#"{"kind":"toaster","frame":{"x":0,"y":0,"width":90,"height":250}}"#) == nil)
        #expect(decode(#"{"kind":"clock"}"#) == nil)
        #expect(decode(#"{"kind":"clock","frame":{"x":0,"y":0}}"#) == nil)
    }

    @Test("Fehlende Kennung wird neu, kaputte Optionen werden Vorgaben")
    func lenient() {
        let widget = decode(#"{"kind":"clock","frame":{"x":0,"y":0,"width":110,"height":250},"options":7}"#)
        #expect(widget?.kind == .clock)
        #expect(widget?.options == WidgetOptions.defaults(for: .clock))
        let partial = decode(#"{"kind":"clock","frame":{"x":0,"y":0,"width":110,"height":250},"options":{"clock":{"showDate":true},"user":5}}"#)
        #expect(partial?.options.clock?.showDate == true)
        #expect(partial?.options.user == nil)
    }

    @Test("Runden auf ganze Punkte")
    func rounding() {
        #expect(WidgetFrame(x: 10.4, y: 10.6, width: 99.5, height: 130).rounded() == WidgetFrame(x: 10, y: 11, width: 100, height: 130))
    }
}
