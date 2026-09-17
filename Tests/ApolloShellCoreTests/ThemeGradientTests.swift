import ApolloShellCore
import Foundation
import Testing

@Suite("Themes: Verläufe lesen")
struct ThemeGradientTests {
    private func gradient(_ text: String) -> ThemeGradient? {
        ThemeValueReader.gradient(text)
    }

    @Test("zwei Farben, ohne Winkel und ohne Stellen")
    func simpleGradient() throws {
        let value = try #require(gradient("linear-gradient(#000000, #ffffff)"))
        #expect(value.angle == 180)
        #expect(value.stops.map(\.color) == [.black, .white])
        #expect(value.stops.map(\.position) == [0, 1])
        #expect(!value.isEmpty)
    }

    @Test("Winkel in Grad und in Worten")
    func angles() throws {
        #expect(try #require(gradient("linear-gradient(45deg, #000, #fff)")).angle == 45)
        #expect(try #require(gradient("linear-gradient(to right, #000, #fff)")).angle == 90)
        #expect(try #require(gradient("linear-gradient(to top left, #000, #fff)")).angle == 315)
        #expect(gradient("linear-gradient(to nowhere, #000, #fff)") == nil)
    }

    @Test("eigene Stellen in Prozent")
    func explicitStops() throws {
        let value = try #require(gradient("linear-gradient(90deg, #ff0000 10%, #00ff00 40%, #0000ff 100%)"))
        #expect(value.stops.map(\.position) == [0.1, 0.4, 1])
        #expect(value.stops.map(\.color) == [ThemeColor(hex: 0xFF0000), ThemeColor(hex: 0x00FF00), ThemeColor(hex: 0x0000FF)])
    }

    @Test("Farben mit Klammern bleiben ein Stueck")
    func functionColors() throws {
        let value = try #require(gradient("linear-gradient(rgb(255, 0, 0), hsl(120, 100%, 50%))"))
        #expect(value.stops.map(\.color) == [ThemeColor(hex: 0xFF0000), ThemeColor(hex: 0x00FF00)])
    }

    @Test("eine Stelle vor ihrer Vorgaengerin wird nach vorne gezogen")
    func positionsNeverGoBackwards() throws {
        let value = try #require(gradient("linear-gradient(#000 60%, #fff 20%)"))
        #expect(value.stops.map(\.position) == [0.6, 0.6])
    }

    @Test("none heisst: kein Verlauf, und das ist kein Fehler")
    func noneIsEmpty() throws {
        let value = try #require(gradient("none"))
        #expect(value.isEmpty)
        #expect(value == ThemeGradient.none)
    }

    @Test("was nicht sicher zu lesen ist, ergibt nichts")
    func rejectsUnreadable() {
        #expect(gradient("") == nil)
        #expect(gradient("linear-gradient(#000)") == nil, "eine Farbe ist kein Verlauf")
        #expect(gradient("radial-gradient(#000, #fff)") == nil, "nur geradlinig")
        #expect(gradient("linear-gradient(#000, #nonsense)") == nil)
        #expect(gradient("#ff0000") == nil, "eine Farbe ist kein Verlauf")
        #expect(gradient("linear-gradient(#111, #222, #333, #444, #555, #666, #777, #888, #999)") == nil,
                "mehr als \(ThemeGradient.maximumStops) Farbstellen")
    }

    @Test("geschrieben und wieder gelesen ergibt denselben Verlauf")
    func roundTrips() throws {
        let original = try #require(gradient("linear-gradient(30deg, #112233 0%, #445566 50%, #778899 100%)"))
        let again = try #require(gradient(original.cssText))
        #expect(again == original)
    }

    @Test("ein Theme setzt einen Verlauf, der Rest bleibt Vorgabe")
    func themeReadsGradients() {
        let sheet = ThemeStyleSheetParser.parse("""
        :root {
          --apollo-bar-gradient: linear-gradient(180deg, #101014 0%, #2a2a33 100%);
        }
        """)
        let theme = Theme.make(identifier: "verlauf", styleSheet: sheet)
        #expect(theme.issues.isEmpty, "\(theme.issues.map(\.description))")
        #expect(theme.gradient(.bar).stops.count == 2)
        #expect(theme.gradient(.bar).stops.first?.color == ThemeColor(hex: 0x101014))
        // Was nicht gesetzt ist, bleibt ohne Verlauf - und die Farbe gilt.
        #expect(theme.gradient(.panel).isEmpty)
        #expect(theme.color(.bar) == ThemeColorToken.bar.defaultValue())
    }

    @Test("unlesbarer Verlauf: Vorgabe und ein Hinweis mit Zeile")
    func unreadableGradientIsReported() {
        let sheet = ThemeStyleSheetParser.parse("""
        :root {
          --apollo-panel-gradient: radial-gradient(#000, #fff);
        }
        """)
        let theme = Theme.make(identifier: "kaputt", styleSheet: sheet)
        #expect(theme.gradient(.panel).isEmpty)
        #expect(theme.issues.contains { $0.description.contains("--apollo-panel-gradient") })
    }
}
