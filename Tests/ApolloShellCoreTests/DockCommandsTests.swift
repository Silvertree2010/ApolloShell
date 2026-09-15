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
}
