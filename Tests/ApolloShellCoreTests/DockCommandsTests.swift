import ApolloShellCore
import Testing

@Suite("The commands of the app in the Dock menu")
struct DockCommandsTests {
    @Test("New commands come along", arguments: ["New Window", "New Private Window", "New OS Window", "Neues Fenster", "Neuer Tab"])
    func newCommands(title: String) {
        #expect(DockCommandFilter.isNewCommand(title))
    }

    @Test("nothing else does", arguments: ["Newsletter", "Open…", "Close Window", "Renew", ""])
    func others(title: String) {
        #expect(!DockCommandFilter.isNewCommand(title))
    }

    // MARK: - By the keyboard shortcut instead of by the text

    @Test("Command-N is a new window, in every language")
    func commandNIsNew() {
        let shortcut = MenuShortcut(character: "n", modifiers: 0)
        #expect(DockCommandFilter.kind(title: "Nouvelle fenêtre", shortcut: shortcut) == .newItem)
        #expect(DockCommandFilter.kind(title: "新規ウインドウ", shortcut: shortcut) == .newItem)
    }

    @Test("Shift-Command-N counts too, for a private window say")
    func shiftCommandNIsNew() {
        #expect(DockCommandFilter.kind(title: "Nouvelle fenêtre privée",
                                       shortcut: MenuShortcut(character: "N", modifiers: 1)) == .newItem)
    }

    @Test("Command-comma is the settings, in every language")
    func commandCommaIsSettings() {
        let shortcut = MenuShortcut(character: ",", modifiers: 0)
        #expect(DockCommandFilter.kind(title: "Réglages…", shortcut: shortcut) == .settings)
        #expect(DockCommandFilter.kind(title: "Einstellungen …", shortcut: shortcut) == .settings)
    }

    @Test("without a shortcut the text decides", arguments: [
        ("Einstellungen …", DockCommandKind.settings),
        ("Settings…", DockCommandKind.settings),
        ("Preferences…", DockCommandKind.settings),
        ("New Window", DockCommandKind.newItem),
        ("Neues Fenster", DockCommandKind.newItem),
    ])
    func titleDecidesWithoutShortcut(title: String, kind: DockCommandKind) {
        #expect(DockCommandFilter.kind(title: title, shortcut: nil) == kind)
    }

    @Test("what neither matches nor is named that way does not come into the menu", arguments: [
        "Open…", "Close Window", "Newsletter", "Print…", "",
    ])
    func unrelatedStaysOut(title: String) {
        #expect(DockCommandFilter.kind(title: title, shortcut: nil) == nil)
    }

    @Test("a shortcut without the command key does not count")
    func withoutCommandKeyItIsNoShortcut() {
        // Bit 3 of the accessibility API means: no ⌘ in this shortcut.
        let shortcut = MenuShortcut(character: "n", modifiers: 8)
        #expect(!shortcut.hasCommand)
        #expect(DockCommandFilter.kind(title: "Nouvelle fenêtre", shortcut: shortcut) == nil)
    }

    @Test("Control-Command-N is no plain new window")
    func controlCommandIsNotNew() {
        #expect(DockCommandFilter.kind(title: "Etwas anderes",
                                       shortcut: MenuShortcut(character: "n", modifiers: 4)) == nil)
    }

    @Test("The shortcut beats the text: Command-N means a new window, even when the text sounds like settings")
    func shortcutWinsOverTitle() {
        #expect(DockCommandFilter.kind(title: "Settings Window",
                                       shortcut: MenuShortcut(character: "n", modifiers: 0)) == .newItem)
    }
}
