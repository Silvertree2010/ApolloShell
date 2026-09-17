import ApolloShellCore
import Testing

@Suite("Befehle der App im Dock-Menue")
struct DockCommandsTests {
    @Test("Neu-Befehle kommen mit", arguments: ["New Window", "New Private Window", "New OS Window", "Neues Fenster", "Neuer Tab"])
    func newCommands(title: String) {
        #expect(DockCommandFilter.isNewCommand(title))
    }

    @Test("alles andere nicht", arguments: ["Newsletter", "Open…", "Close Window", "Renew", ""])
    func others(title: String) {
        #expect(!DockCommandFilter.isNewCommand(title))
    }

    // MARK: - Nach Tastenkuerzel statt nach Text

    @Test("Befehl-N ist ein neues Fenster, in jeder Sprache")
    func commandNIsNew() {
        let shortcut = MenuShortcut(character: "n", modifiers: 0)
        #expect(DockCommandFilter.kind(title: "Nouvelle fenêtre", shortcut: shortcut) == .newItem)
        #expect(DockCommandFilter.kind(title: "新規ウインドウ", shortcut: shortcut) == .newItem)
    }

    @Test("Umschalt-Befehl-N zaehlt auch, etwa fuer ein privates Fenster")
    func shiftCommandNIsNew() {
        #expect(DockCommandFilter.kind(title: "Nouvelle fenêtre privée",
                                       shortcut: MenuShortcut(character: "N", modifiers: 1)) == .newItem)
    }

    @Test("Befehl-Komma sind die Einstellungen, in jeder Sprache")
    func commandCommaIsSettings() {
        let shortcut = MenuShortcut(character: ",", modifiers: 0)
        #expect(DockCommandFilter.kind(title: "Réglages…", shortcut: shortcut) == .settings)
        #expect(DockCommandFilter.kind(title: "Einstellungen …", shortcut: shortcut) == .settings)
    }

    @Test("ohne Kuerzel entscheidet der Text", arguments: [
        ("Einstellungen …", DockCommandKind.settings),
        ("Settings…", DockCommandKind.settings),
        ("Preferences…", DockCommandKind.settings),
        ("New Window", DockCommandKind.newItem),
        ("Neues Fenster", DockCommandKind.newItem),
    ])
    func titleDecidesWithoutShortcut(title: String, kind: DockCommandKind) {
        #expect(DockCommandFilter.kind(title: title, shortcut: nil) == kind)
    }

    @Test("was weder passt noch heisst, kommt nicht ins Menue", arguments: [
        "Open…", "Close Window", "Newsletter", "Print…", "",
    ])
    func unrelatedStaysOut(title: String) {
        #expect(DockCommandFilter.kind(title: title, shortcut: nil) == nil)
    }

    @Test("ein Kuerzel ohne Befehlstaste zaehlt nicht")
    func withoutCommandKeyItIsNoShortcut() {
        // Bit 3 der Bedienungshilfen heisst: kein ⌘ in diesem Kuerzel.
        let shortcut = MenuShortcut(character: "n", modifiers: 8)
        #expect(!shortcut.hasCommand)
        #expect(DockCommandFilter.kind(title: "Nouvelle fenêtre", shortcut: shortcut) == nil)
    }

    @Test("Strg-Befehl-N ist kein einfaches neues Fenster")
    func controlCommandIsNotNew() {
        #expect(DockCommandFilter.kind(title: "Etwas anderes",
                                       shortcut: MenuShortcut(character: "n", modifiers: 4)) == nil)
    }

    @Test("Kuerzel schlaegt Text: Befehl-N heisst neues Fenster, auch wenn der Text nach Einstellungen klingt")
    func shortcutWinsOverTitle() {
        #expect(DockCommandFilter.kind(title: "Settings Window",
                                       shortcut: MenuShortcut(character: "n", modifiers: 0)) == .newItem)
    }
}
