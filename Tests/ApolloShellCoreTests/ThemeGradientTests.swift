import ApolloShellCore
import Foundation
import Testing

@Suite("Themes: reading gradients")
struct ThemeGradientTests {
    private func gradient(_ text: String) -> ThemeGradient? {
        ThemeValueReader.gradient(text)
    }

    @Test("two colors, without an angle and without positions")
    func simpleGradient() throws {
        let value = try #require(gradient("linear-gradient(#000000, #ffffff)"))
        #expect(value.angle == 180)
        #expect(value.stops.map(\.color) == [.black, .white])
        #expect(value.stops.map(\.position) == [0, 1])
        #expect(!value.isEmpty)
    }

    @Test("the angle in degrees and in words")
    func angles() throws {
        #expect(try #require(gradient("linear-gradient(45deg, #000, #fff)")).angle == 45)
        #expect(try #require(gradient("linear-gradient(to right, #000, #fff)")).angle == 90)
        #expect(try #require(gradient("linear-gradient(to top left, #000, #fff)")).angle == 315)
        #expect(gradient("linear-gradient(to nowhere, #000, #fff)") == nil)
    }

    @Test("positions of one's own in percent")
    func explicitStops() throws {
        let value = try #require(gradient("linear-gradient(90deg, #ff0000 10%, #00ff00 40%, #0000ff 100%)"))
        #expect(value.stops.map(\.position) == [0.1, 0.4, 1])
        #expect(value.stops.map(\.color) == [ThemeColor(hex: 0xFF0000), ThemeColor(hex: 0x00FF00), ThemeColor(hex: 0x0000FF)])
    }

    @Test("colors with brackets stay one piece")
    func functionColors() throws {
        let value = try #require(gradient("linear-gradient(rgb(255, 0, 0), hsl(120, 100%, 50%))"))
        #expect(value.stops.map(\.color) == [ThemeColor(hex: 0xFF0000), ThemeColor(hex: 0x00FF00)])
    }

    @Test("a position before its predecessor is pulled forward")
    func positionsNeverGoBackwards() throws {
        let value = try #require(gradient("linear-gradient(#000 60%, #fff 20%)"))
        #expect(value.stops.map(\.position) == [0.6, 0.6])
    }

    @Test("a tab may stand between the color and the position too")
    func acceptsAnyWhitespaceBeforeThePosition() throws {
        let value = try #require(gradient("linear-gradient(#000000\t25%, #ffffff 100%)"))
        #expect(value.stops.map(\.position) == [0.25, 1])
    }

    @Test("none means: no gradient, and that is no error")
    func noneIsEmpty() throws {
        let value = try #require(gradient("none"))
        #expect(value.isEmpty)
        #expect(value == ThemeGradient.none)
    }

    @Test("what cannot be read safely gives nothing")
    func rejectsUnreadable() {
        #expect(gradient("") == nil)
        #expect(gradient("linear-gradient(#000)") == nil, "eine Farbe ist kein Verlauf")
        #expect(gradient("radial-gradient(#000, #fff)") == nil, "nur geradlinig")
        #expect(gradient("linear-gradient(#000, #nonsense)") == nil)
        #expect(gradient("#ff0000") == nil, "eine Farbe ist kein Verlauf")
        #expect(gradient("linear-gradient(#111, #222, #333, #444, #555, #666, #777, #888, #999)") == nil,
                "mehr als \(ThemeGradient.maximumStops) Farbstellen")
    }

    @Test("written and read back gives the same gradient")
    func roundTrips() throws {
        let original = try #require(gradient("linear-gradient(30deg, #112233 0%, #445566 50%, #778899 100%)"))
        let again = try #require(gradient(original.cssText))
        #expect(again == original)
    }

    @Test("a theme sets a gradient, the rest stays the default")
    func themeReadsGradients() {
        let sheet = ThemeStyleSheetParser.parse("""
        :root {
          --apollo-bar-gradient: linear-gradient(180deg, #101014 0%, #2a2a33 100%);
        }
        """)
        let theme = Theme.make(identifier: "verlauf", styleSheet: sheet)
        #expect(theme.issues.isEmpty, "\(theme.issues.map(\.description))")
        #expect(theme.gradient(.bar)?.stops.count == 2)
        #expect(theme.gradient(.bar)?.stops.first?.color == ThemeColor(hex: 0x101014))
        // What is not set stays empty - the gradient like the color.
        #expect(theme.gradient(.panel) == nil)
        #expect(theme.color(.bar) == nil)
    }

    @Test("an unreadable gradient: the default and a notice with a line")
    func unreadableGradientIsReported() {
        let sheet = ThemeStyleSheetParser.parse("""
        :root {
          --apollo-panel-gradient: radial-gradient(#000, #fff);
        }
        """)
        let theme = Theme.make(identifier: "kaputt", styleSheet: sheet)
        #expect(theme.gradient(.panel) == nil)
        #expect(theme.issues.contains { $0.description.contains("--apollo-panel-gradient") })
    }
}

@Suite("Themes: the direction of a gradient")
struct ThemeGradientDirectionTests {
    private func gradient(_ angle: Double) -> ThemeGradient {
        ThemeGradient(angle: angle, stops: [
            ThemeGradient.Stop(color: .black, position: 0),
            ThemeGradient.Stop(color: .white, position: 1),
        ])
    }

    private func close(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) < 0.0001
    }

    @Test("180 degrees runs from top to bottom - the first color stands at the top")
    func downwards() {
        let points = gradient(180).points
        #expect(close(points.start.y, 0) && close(points.start.x, 0.5))
        #expect(close(points.end.y, 1) && close(points.end.x, 0.5))
    }

    @Test("0 degrees runs upwards")
    func upwards() {
        let points = gradient(0).points
        #expect(close(points.start.y, 1))
        #expect(close(points.end.y, 0))
    }

    @Test("90 degrees runs to the right")
    func rightwards() {
        let points = gradient(90).points
        #expect(close(points.start.x, 0) && close(points.start.y, 0.5))
        #expect(close(points.end.x, 1) && close(points.end.y, 0.5))
    }

    @Test("270 degrees runs to the left")
    func leftwards() {
        let points = gradient(270).points
        #expect(close(points.start.x, 1))
        #expect(close(points.end.x, 0))
    }

    @Test("135 degrees runs to the bottom right")
    func diagonally() {
        let points = gradient(135).points
        #expect(points.start.x < 0.5 && points.start.y < 0.5, "Anfang oben links")
        #expect(points.end.x > 0.5 && points.end.y > 0.5, "Ende unten rechts")
    }
}
