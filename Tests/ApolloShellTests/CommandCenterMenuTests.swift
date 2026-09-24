import Testing
import AppKit
import ApolloControl
@testable import ApolloShell

@MainActor
@Suite("Kommandozentrale als NSMenu")
struct CommandCenterMenuTests {
    static func model() -> [MenuEntry] {
        var state = CommandCenterState(
            configs: [CommandCenterState.Config(id: "apolloshell-default", isActive: true)],
            themes: [CommandCenterState.Theme(id: "Nord", issueCount: 1, isActive: true)],
            timeZone: TimeZone(identifier: "UTC")!
        )
        state.update = .checking
        return CommandCenterModel.build(nil, state: state)
    }

    @Test("Titel, Trennlinien und Kürzel wie im Modell")
    func structure() throws {
        let builder = CommandCenterMenu { _ in }
        let menu = builder.make(Self.model())
        #expect(menu.items.map { $0.isSeparatorItem ? "---" : $0.title } == [
            "Reload Config", "Restart ApolloShell", "---", "Config", "Theme", "---",
            "Updates", "Crash Reports", "Start at Login", "Install Command Line Tool…", "---",
            "About ApolloShell", "Quit ApolloShell",
        ])
        let reload = menu.items[0]
        #expect(reload.keyEquivalent == "r")
        #expect(reload.keyEquivalentModifierMask == .command)
        #expect(menu.items[12].keyEquivalent == "q")
        #expect(menu.autoenablesItems == false)
    }

    @Test("Untermenüs, Häkchen und deaktivierte Statuszeile")
    func submenus() throws {
        let menu = CommandCenterMenu { _ in }.make(Self.model())
        let config = try #require(menu.items[3].submenu)
        #expect(config.items[0].state == .on)
        let theme = try #require(menu.items[4].submenu)
        #expect(theme.items.map(\.title).contains("Show Theme Issues (1)"))
        let updates = try #require(menu.items[6].submenu)
        #expect(updates.items[0].title == "Checking…")
        #expect(updates.items[0].isEnabled == false)
    }

    @Test("Auswahl ruft den Befehl des Eintrags auf")
    func selection() throws {
        var chosen: [MenuCommand] = []
        let builder = CommandCenterMenu { chosen.append($0) }
        let menu = builder.make(Self.model())
        let theme = try #require(menu.items[4].submenu)
        let none = try #require(theme.items.first { $0.title == "None" })
        builder.choose(none)
        builder.choose(menu.items[12])
        #expect(chosen == [.selectTheme(nil), .quit])
        #expect(menu.items[12].target === builder)
    }

    @Test("Abschnittsüberschrift und Anzeige-Kürzel eigener Einträge")
    func headerAndDisplayShortcut() throws {
        let entries = CommandCenterModel.build(
            CommandCenterSpec(entries: [.item(MenuItemSpec(title: "Launcher", shortcut: "alt+space", handler: "h"))]),
            state: CommandCenterState(configs: [], themes: [])
        )
        let menu = CommandCenterMenu { _ in }.make(entries)
        #expect(menu.items[0].keyEquivalent == " ")
        #expect(menu.items[0].keyEquivalentModifierMask == .option)
        let header = try #require(menu.items.first { $0.title == "ApolloShell" })
        #expect(header.isSectionHeader)
    }
}
