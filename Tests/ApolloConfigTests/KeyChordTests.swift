import Testing
import ApolloShellCore
@testable import ApolloConfig

@Suite("Tastenkombinationen")
struct KeyChordTests {
    static let valid: [(String, String, String)] = [
        ("alt+space", "alt+space", "⌥Space"),
        ("opt+space", "alt+space", "⌥Space"),
        ("option+space", "alt+space", "⌥Space"),
        ("ctrl+alt+d", "ctrl+alt+d", "⌃⌥D"),
        ("cmd+shift+ctrl+alt+d", "hyper+d", "⌃⌥⇧⌘D"),
        ("hyper+comma", "hyper+comma", "⌃⌥⇧⌘,"),
        ("f20", "f20", "F20"),
        ("cmd+f13", "cmd+f13", "⌘F13"),
        ("escape", "escape", "⎋"),
        ("esc", "escape", "⎋"),
        ("enter", "return", "↩"),
        ("keypad-enter", "keypad-enter", "⌅"),
        ("alt+forward-delete", "alt+forward-delete", "⌥⌦"),
        ("backspace", "delete", "⌫"),
        ("ctrl+left", "ctrl+left", "⌃←"),
        ("shift+[", "shift+[", "⇧["),
        ("alt+-", "alt+minus", "⌥-"),
        ("cmd+quote", "cmd+quote", "⌘'"),
        ("CMD+O", "cmd+o", "⌘O"),
        ("pageup", "pageup", "⇞"),
        ("tab", "tab", "⇥"),
    ]

    @Test("gültige Kombinationen: kanonische Form und Anzeige", arguments: KeyChordTests.valid)
    func parsesValid(text: String, canonical: String, display: String) throws {
        let chord = try #require(KeyChord.parse(text))
        #expect(chord.canonical == canonical)
        #expect(chord.display == display)
    }

    @Test("ungültige Kombinationen", arguments: ["", "alt+", "+a", "alt++", "alt+nokey", "super+a", "alt + space", "f21", "cmd+alt"])
    func rejectsInvalid(text: String) {
        #expect(KeyChord.parse(text) == nil)
    }

    @Test("Tastencodes stimmen mit HotKeyKey aus 0.1.4.2 überein")
    func keyCodes() throws {
        #expect(try #require(KeyChord.parse("space")).keyCode == HotKeyKey.space)
        #expect(try #require(KeyChord.parse("escape")).keyCode == HotKeyKey.escape)
        #expect(try #require(KeyChord.parse("delete")).keyCode == HotKeyKey.delete)
        #expect(try #require(KeyChord.parse("forward-delete")).keyCode == HotKeyKey.forwardDelete)
        #expect(try #require(KeyChord.parse("d")).keyCode == HotKeyKey.d)
        #expect(try #require(KeyChord.parse("u")).keyCode == HotKeyKey.u)
        #expect(try #require(KeyChord.parse("comma")).keyCode == HotKeyKey.comma)
        #expect(try #require(KeyChord.parse("f20")).keyCode == HotKeyKey.f20)
        #expect(try #require(KeyChord.parse("ctrl+alt+d")).hotKey == HotKey(keyCode: HotKeyKey.d, modifiers: [.control, .option]))
    }

    @Test("jede Taste aus blocks.md 7.2 ist bekannt")
    func everyKeyName() {
        let letters = "abcdefghijklmnopqrstuvwxyz".map(String.init)
        let digits = (0...9).map(String.init)
        let functionKeys = (1...20).map { "f\($0)" }
        let named = [
            "space", "return", "enter", "tab", "escape", "esc", "delete", "forward-delete", "left", "right", "up", "down",
            "home", "end", "pageup", "pagedown", "minus", "equal", "comma", "period", "slash", "semicolon", "quote",
            "grave", "backslash", "[", "]", "keypad-enter",
        ]
        for name in letters + digits + functionKeys + named {
            #expect(KeyChord.parse("cmd+" + name) != nil, "\(name)")
        }
    }
}
