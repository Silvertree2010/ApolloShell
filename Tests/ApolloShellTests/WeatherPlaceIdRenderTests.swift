import Testing
import Foundation
@testable import ApolloShell

@MainActor
@Suite("Render: Wetter-Widget liest place-id", .serialized)
struct WeatherPlaceIdRenderTests {
    @Test("Wetter-Karte: mit Ort Temperatur und Symbol, ohne Ort die Ortswahl")
    func placeId() throws {
        let ready = try DefaultRenderTests.shot("dash", state: "g2-wx-ready")
        let none = try DefaultRenderTests.shot("dash", state: "g2-wx-none")
        #expect(ready.size == none.size)
        let ink = { (c: RGBA) in c.r < 90 && c.g < 90 && c.b < 90 }
        #expect(ready.count(where: ink) != none.count(where: ink))
        let accent = { (c: RGBA) in max(c.r, c.g, c.b) - min(c.r, c.g, c.b) > 80 }
        #expect(none.count(where: accent) > 0)
    }
}
