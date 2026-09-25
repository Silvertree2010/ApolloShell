import ApolloShellCore
import Testing
@testable import ApolloStyle

@Suite("CSS: Farben")
struct CSSColorTests {
    private func color(_ text: String) throws -> CSSColor {
        try CSSColorParser.color(CSSComponentParser.parse(text: text))
    }

    private func rgba(_ hex: UInt32, _ alpha: Double = 1) -> CSSColor {
        CSSColorParser.rgba(ThemeColor(hex: hex, alpha: alpha))
    }

    @Test("dieselben Schreibweisen wie in Themes",
          arguments: [
              ("#f00", 0xFF0000, 1.0),
              ("#ff000080", 0xFF0000, 128.0 / 255),
              ("#112233", 0x112233, 1.0),
              ("rgb(17, 34, 51)", 0x112233, 1.0),
              ("rgba(17 34 51 / 50%)", 0x112233, 0.5),
              ("hsl(0, 100%, 50%)", 0xFF0000, 1.0),
              ("hsla(120deg 100% 25% / 0.5)", 0x008000, 0.5),
              ("orange", 0xFFA500, 1.0),
              ("TRANSPARENT", 0x000000, 0.0),
          ])
    func themeForms(text: String, hex: Int, alpha: Double) throws {
        #expect(try color(text) == rgba(UInt32(hex), alpha))
    }

    @Test("currentcolor bleibt symbolisch")
    func currentColor() throws {
        #expect(try color("currentColor") == .currentColor)
    }

    @Test("jede Systemfarbe aus der Spec bleibt symbolisch", arguments: CSSColorParser.systemColorNames)
    func systemColors(name: String) throws {
        #expect(try color(name) == .system(name: name, alpha: 1))
        #expect(try color(name.uppercased()) == .system(name: name, alpha: 1))
    }

    @Test("die Liste der Systemfarben ist vollständig")
    func systemColorCount() {
        #expect(CSSColorParser.systemColorNames.count == 24)
        #expect(CSSColorParser.systemColorNames.contains("-apple-system-selected-content-background"))
        #expect(CSSColorParser.systemColorNames.contains("-apple-system-mint"))
    }

    @Test("relative Farbe: Systemfarbe halb durchsichtig")
    func relativeSystem() throws {
        #expect(try color("rgb(from -apple-system-label r g b / 0.14)") == .system(name: "-apple-system-label", alpha: 0.14))
        #expect(try color("rgb(from -apple-system-window-background r g b / 70%)") == .system(name: "-apple-system-window-background", alpha: 0.7))
    }

    @Test("relative Farbe: feste Farbe bekommt die neue Deckkraft")
    func relativeFixed() throws {
        #expect(try color("rgb(from #ff0000 r g b / 0.5)") == .rgba(red: 1, green: 0, blue: 0, alpha: 0.5))
        #expect(try color("rgb(from rgb(from #00ff00 r g b / 0.2) r g b / 1)") == .rgba(red: 0, green: 1, blue: 0, alpha: 1))
    }

    @Test("nur die Form r g b / alpha ist erlaubt",
          arguments: [
              "rgb(from red g r b / 1)",
              "rgb(from red r g b)",
              "rgba(from red r g b / 1)",
              "rgb(from currentcolor r g b / 0.5)",
              "rgb(from red r g b / 1deg)",
          ])
    func relativeRejected(text: String) {
        #expect(throws: CSSValueError.self) { try color(text) }
    }

    @Test("Unbekanntes wird abgelehnt",
          arguments: ["-apple-system-foo", "#12", "rgb(1, 2)", "notacolor", "12px", "linear-gradient(red, blue)"])
    func rejected(text: String) {
        #expect(throws: CSSValueError.self) { try color(text) }
    }
}
