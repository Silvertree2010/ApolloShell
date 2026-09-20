import ApolloShellCore
import Testing

@Suite("Themes: reading individual values")
struct ThemeValueReaderTests {
    @Test("Colors", arguments: [
        ("#fff", ThemeColor(hex: 0xFFFFFF)),
        ("#FFFFFF", ThemeColor(hex: 0xFFFFFF)),
        ("#ff0000", ThemeColor(hex: 0xFF0000)),
        ("#f00", ThemeColor(hex: 0xFF0000)),
        ("#f008", ThemeColor(hex: 0xFF0000, alpha: 0x88 / 255)),
        ("#ff000080", ThemeColor(hex: 0xFF0000, alpha: 0x80 / 255)),
        ("rgb(255, 0, 0)", ThemeColor(hex: 0xFF0000)),
        ("rgb(255 0 0)", ThemeColor(hex: 0xFF0000)),
        ("rgba(255, 0, 0, 0.5)", ThemeColor(hex: 0xFF0000, alpha: 0.5)),
        ("rgb(255 0 0 / 50%)", ThemeColor(hex: 0xFF0000, alpha: 0.5)),
        ("rgb(100%, 0%, 0%)", ThemeColor(hex: 0xFF0000)),
        ("hsl(0, 100%, 50%)", ThemeColor(hex: 0xFF0000)),
        ("hsl(120 100% 25%)", ThemeColor(hex: 0x008000)),
        ("hsl(0deg 0% 100%)", ThemeColor(hex: 0xFFFFFF)),
        ("hsla(0, 0%, 0%, 0)", ThemeColor(red: 0, green: 0, blue: 0, alpha: 0)),
        ("red", ThemeColor(hex: 0xFF0000)),
        ("RED", ThemeColor(hex: 0xFF0000)),
        ("orange", ThemeColor(hex: 0xFFA500)),
        ("transparent", ThemeColor.clear),
    ])
    func colors(text: String, expected: ThemeColor) {
        #expect(ThemeValueReader.read(text, kind: .color) == .color(expected))
    }

    @Test("not a color", arguments: [
        "", "#", "#12", "#12345", "#gg0000", "rgb(1, 2)", "rgb(1, 2, 3, 4, 5)", "rgb(1 2 3",
        "hsl(1, 2)", "nope", "url(x.png)", "12px", "rgb(nan, 0, 0)", "rgb(inf, 0, 0)",
        "#ff0000 #00ff00", "var(--other)", "rebeccapurple",
    ])
    func notColors(text: String) {
        #expect(ThemeValueReader.read(text, kind: .color) == nil)
    }

    private static let length = ThemeTokenKind.number(ThemeNumberSpec(unit: .points, minimum: -100, maximum: 100))
    private static let ratio = ThemeTokenKind.number(ThemeNumberSpec(unit: .ratio, minimum: 0, maximum: 1))
    private static let scalar = ThemeTokenKind.number(ThemeNumberSpec(unit: .scalar, minimum: 0, maximum: 1000))

    @Test("Lengths", arguments: [
        ("12px", 12.0), ("12pt", 12.0), ("12", 12.0), ("12.5px", 12.5), ("-3px", -3.0),
        (".5px", 0.5), ("+4px", 4.0), ("0", 0.0), ("12PX", 12.0), (" 12px ", 12.0),
    ])
    func lengths(text: String, expected: Double) {
        #expect(ThemeValueReader.read(text, kind: Self.length) == .number(expected))
    }

    @Test("not a length", arguments: ["", "px", "50%", "abc", "12em", "1e3", "0x10", "nan", "inf", "12 34"])
    func notLengths(text: String) {
        #expect(ThemeValueReader.read(text, kind: Self.length) == nil)
    }

    @Test("Ratios", arguments: [("0.5", 0.5), ("50%", 0.5), ("1", 1.0), ("0", 0.0), (".25", 0.25), ("100%", 1.0)])
    func ratios(text: String, expected: Double) {
        #expect(ThemeValueReader.read(text, kind: Self.ratio) == .number(expected))
    }

    @Test("plain numbers", arguments: [("400", 400.0), ("1", 1.0), ("1.5", 1.5)])
    func scalars(text: String, expected: Double) {
        #expect(ThemeValueReader.read(text, kind: Self.scalar) == .number(expected))
    }

    @Test("a plain number takes no unit", arguments: ["400px", "50%", "400pt"])
    func scalarsRejectUnits(text: String) {
        #expect(ThemeValueReader.read(text, kind: Self.scalar) == nil)
    }

    @Test("Texts", arguments: [
        ("\"Alex\"", "Alex"),
        ("'Alex'", "Alex"),
        ("\"\"", ""),
        ("Inter", "Inter"),
        ("\"SF Mono\", monospace", "\"SF Mono\", monospace"),
        ("\"Zeile\\\"mit\"", "Zeile\"mit"),
        ("\"a lot     of space\"", "a lot of space"),
    ])
    func texts(text: String, expected: String) {
        #expect(ThemeValueReader.read(text, kind: .text) == .text(expected))
    }

    @Test("Text without control characters and without line breaks")
    func textWithoutControlCharacters() {
        #expect(ThemeValueReader.read("\"a\u{0}b\u{7}c\"", kind: .text) == .text("abc"))
    }

    @Test("Files", arguments: [
        ("url(\"bg.png\")", "bg.png"),
        ("url(bg.png)", "bg.png"),
        ("URL(\"bg.png\")", "bg.png"),
        ("\"bg.png\"", "bg.png"),
        ("url(\"sub/bg.png\")", "sub/bg.png"),
        ("none", ""),
        ("url()", ""),
    ])
    func files(text: String, expected: String) {
        #expect(ThemeValueReader.read(text, kind: .file) == .file(ThemeAsset(reference: expected, url: nil)))
    }

    @Test("not a file", arguments: ["bg.png", "", "12px", "var(--bg)"])
    func notFiles(text: String) {
        #expect(ThemeValueReader.read(text, kind: .file) == nil)
    }

    private static let fit = ThemeTokenKind.option(["fill", "fit", "tile"])

    @Test("Enumerations", arguments: [("fill", "fill"), ("FILL", "fill"), (" tile ", "tile")])
    func options(text: String, expected: String) {
        #expect(ThemeValueReader.read(text, kind: Self.fit) == .option(expected))
    }

    @Test("unknown word in an enumeration", arguments: ["stretch", "", "1", "\"fill\""])
    func unknownOptions(text: String) {
        #expect(ThemeValueReader.read(text, kind: Self.fit) == nil)
    }

    @Test("Yes and No", arguments: [
        ("true", true), ("yes", true), ("on", true), ("1", true), ("TRUE", true),
        ("false", false), ("no", false), ("off", false), ("0", false),
    ])
    func flags(text: String, expected: Bool) {
        #expect(ThemeValueReader.read(text, kind: .flag) == .flag(expected))
    }

    @Test("neither Yes nor No", arguments: ["vielleicht", "", "2", "ja"])
    func notFlags(text: String) {
        #expect(ThemeValueReader.read(text, kind: .flag) == nil)
    }

    @Test("!important is stripped off")
    func important() {
        #expect(ThemeValueReader.read("red !important", kind: .color) == .color(ThemeColor(hex: 0xFF0000)))
        #expect(ThemeValueReader.read("12px!IMPORTANT", kind: Self.length) == .number(12))
    }

    @Test("var() does not exist - better the default than a guessed value", arguments: [
        ThemeTokenKind.color, ThemeTokenKind.text, ThemeTokenKind.file, ThemeTokenKind.flag,
    ])
    func noVariables(kind: ThemeTokenKind) {
        #expect(ThemeValueReader.read("var(--something)", kind: kind) == nil)
    }

    @Test("opacity and ratios stay in range 0...1")
    func alphaStaysInRange() {
        #expect(ThemeValueReader.read("rgba(0, 0, 0, 5)", kind: .color)?.color?.alpha == 1)
        #expect(ThemeValueReader.read("rgba(0, 0, 0, -5)", kind: .color)?.color?.alpha == 0)
        #expect(ThemeValueReader.read("rgb(300, -20, 0)", kind: .color)?.color == ThemeColor(hex: 0xFF0000))
    }
}
