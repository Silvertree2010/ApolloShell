import Testing
import Foundation
import ApolloConfig
import ApolloShellCore
@testable import ApolloControl

@Suite("Kommandozentrale als Modell")
struct CommandCenterModelTests {
    static let zurich = TimeZone(identifier: "Europe/Zurich")!
    static let checkedAt = Date(timeIntervalSince1970: 1_790_000_000)

    static func state(_ change: (inout CommandCenterState) -> Void = { _ in }) -> CommandCenterState {
        var state = CommandCenterState(
            configs: [
                CommandCenterState.Config(id: "apolloshell-default", isActive: true),
                CommandCenterState.Config(id: "launcher-only", isActive: false),
            ],
            themes: [
                CommandCenterState.Theme(id: "Afterglow", issueCount: 0, isActive: false),
                CommandCenterState.Theme(id: "Nord", issueCount: 2, isActive: false),
            ],
            timeZone: zurich
        )
        change(&state)
        return state
    }

    static func titles(_ entries: [MenuEntry]) -> [String] {
        entries.map { $0.kind == .separator ? "---" : $0.title }
    }

    static func entry(_ title: String, in entries: [MenuEntry]) -> MenuEntry? {
        entries.first { $0.title == title }
    }

    @Test("Vorgabe nach runtime.md 7.1")
    func defaultLayout() {
        let menu = CommandCenterModel.build(nil, state: Self.state())
        #expect(Self.titles(menu) == [
            "Reload Config", "Restart ApolloShell", "---",
            "Config", "Theme", "---",
            "Updates", "Crash Reports", "Start at Login", "Install Command Line Tool…", "---",
            "About ApolloShell", "Quit ApolloShell",
        ])
        #expect(Self.entry("Reload Config", in: menu)?.shortcut == "cmd+r")
        #expect(Self.entry("Quit ApolloShell", in: menu)?.shortcut == "cmd+q")
        #expect(Self.entry("Reload Config", in: menu)?.command == .reloadConfig)
        #expect(Self.entry("Quit ApolloShell", in: menu)?.command == .quit)
    }

    @Test("Show Problems, Marketplace und Install CLI nur unter ihren Bedingungen")
    func conditionalEntries() {
        let menu = CommandCenterModel.build(nil, state: Self.state {
            $0.problemCount = 3
            $0.marketplaceEnabled = true
            $0.cliInstalled = true
        })
        #expect(Self.titles(menu).prefix(7) == ["Reload Config", "Restart ApolloShell", "Show Problems (3)", "---", "Config", "Theme", "Marketplace…"])
        #expect(Self.entry("Show Problems (3)", in: menu)?.command == .showProblems)
        #expect(Self.entry("Install Command Line Tool…", in: menu) == nil)
        let brew = CommandCenterModel.build(nil, state: Self.state { $0.installKind = .homebrew })
        #expect(Self.entry("Install Command Line Tool…", in: brew) == nil)
    }

    @Test("Config-Untermenü mit Häkchen an der aktiven")
    func configSubmenu() throws {
        let menu = CommandCenterModel.build(nil, state: Self.state())
        let children = try #require(Self.entry("Config", in: menu)?.children)
        #expect(Self.titles(children) == ["apolloshell-default", "launcher-only", "---", "Open Config Folder", "Copy to Own Config…"])
        #expect(children[0].checked && !children[1].checked)
        #expect(children[1].command == .selectConfig("launcher-only"))
        #expect(children[4].command == .copyToOwnConfig)
    }

    @Test("Theme-Untermenü: None, Liste, Hinweise nur beim gewählten Theme, Add Theme…")
    func themeSubmenu() throws {
        let none = try #require(Self.entry("Theme", in: CommandCenterModel.build(nil, state: Self.state()))?.children)
        #expect(Self.titles(none) == ["None", "Afterglow", "Nord", "---", "Add Theme…", "Open Themes Folder"])
        #expect(none[0].checked)
        #expect(none[0].command == .selectTheme(nil))
        let nord = try #require(Self.entry("Theme", in: CommandCenterModel.build(nil, state: Self.state { $0.themes[1].isActive = true }))?.children)
        #expect(Self.titles(nord) == ["None", "Afterglow", "Nord", "---", "Show Theme Issues (2)", "Add Theme…", "Open Themes Folder"])
        #expect(!nord[0].checked && nord[2].checked)
        #expect(nord[4].command == .showThemeIssues("Nord"))
        #expect(nord[5].command == .addTheme)
        let clean = try #require(Self.entry("Theme", in: CommandCenterModel.build(nil, state: Self.state { $0.themes[0].isActive = true }))?.children)
        #expect(!Self.titles(clean).contains { $0.hasPrefix("Show Theme Issues") })
    }

    @Test("Update-Statuszeilen")
    func updateStatusLines() {
        func line(_ status: UpdateStatus, lastCheck: Date? = nil) -> String {
            let menu = CommandCenterModel.build(nil, state: Self.state {
                $0.update = status
                $0.lastUpdateCheck = lastCheck
            })
            let first = Self.entry("Updates", in: menu)?.children?.first
            #expect(first?.enabled == false)
            return first?.title ?? ""
        }
        #expect(line(.upToDate, lastCheck: Self.checkedAt) == "Up to Date · checked 16:13")
        #expect(line(.upToDate) == "Up to Date")
        #expect(line(.checking) == "Checking…")
        #expect(line(.available(version: "0.2.1")) == "Version 0.2.1 Available")
        #expect(line(.ready(version: "0.2.1")) == "Version 0.2.1 Available")
        #expect(line(.failed("offline")) == "Failed: offline")
        #expect(line(.unavailable) == "This Build Cannot Update Itself")
        #expect(line(.idle) == "Not Checked Yet")
        #expect(line(.idle, lastCheck: Self.checkedAt) == "Last Checked 16:13")
    }

    @Test("Updates-Untermenü für DMG")
    func updatesDisk() throws {
        let menu = CommandCenterModel.build(nil, state: Self.state {
            $0.update = .ready(version: "0.2.1")
            $0.releaseNotes = URL(string: "https://example.com/notes")
            $0.autoCheck = true
            $0.autoInstall = false
        })
        let children = try #require(Self.entry("Updates", in: menu)?.children)
        #expect(Self.titles(children) == ["Version 0.2.1 Available", "Restart to Install 0.2.1", "Release Notes", "---", "Check for Updates…", "Check Automatically", "Install Automatically"])
        #expect(children[1].command == .installUpdate)
        #expect(children[2].command == .releaseNotes(URL(string: "https://example.com/notes")!))
        #expect(children[5].checked && !children[6].checked)
        #expect(children[6].command == .setAutoInstall(true))
        #expect(children[5].command == .setAutoCheck(false))
        let waiting = try #require(Self.entry("Updates", in: CommandCenterModel.build(nil, state: Self.state { $0.update = .available(version: "0.2.1") }))?.children)
        #expect(!Self.titles(waiting).contains { $0.hasPrefix("Restart to Install") })
        #expect(!Self.titles(waiting).contains("Release Notes"))
    }

    @Test("Updates-Untermenü für Homebrew")
    func updatesHomebrew() throws {
        let menu = CommandCenterModel.build(nil, state: Self.state { $0.installKind = .homebrew })
        let children = try #require(Self.entry("Updates", in: menu)?.children)
        #expect(Self.titles(children) == ["Not Checked Yet", "---", "Check for Updates…", "Check Automatically", "Copy brew upgrade apolloshell"])
        #expect(children[4].command == .copyBrewUpgrade)
    }

    @Test("Crash Reports und Start at Login zeigen den Zustand")
    func crashReportsAndLogin() throws {
        let menu = CommandCenterModel.build(nil, state: Self.state {
            $0.crashReports = .never
            $0.startsAtLogin = true
        })
        let crash = try #require(Self.entry("Crash Reports", in: menu)?.children)
        #expect(Self.titles(crash) == ["Ask", "Always Send", "Never Send"])
        #expect(crash.map(\.checked) == [false, false, true])
        #expect(crash[1].command == .crashReports(.always))
        #expect(Self.entry("Start at Login", in: menu)?.checked == true)
        #expect(Self.entry("Start at Login", in: menu)?.command == .setStartAtLogin(false))
    }

    @Test("eigene Liste nach 7.2 ersetzt die Vorgabe")
    func customList() {
        let spec = CommandCenterSpec(entries: [
            .builtin("reload-config"),
            .builtin("configs"),
            .builtin("themes"),
            .separator,
            .item(MenuItemSpec(title: "Settings…", handler: "h1")),
            .item(MenuItemSpec(title: "Launcher", shortcut: "alt+space", handler: "h2")),
            .separator,
            .builtin("quit"),
        ])
        let menu = CommandCenterModel.build(spec, state: Self.state())
        #expect(Self.titles(menu) == ["Reload Config", "Config", "Theme", "---", "Settings…", "Launcher", "---", "Quit ApolloShell"])
        #expect(menu[5].shortcut == "alt+space")
        #expect(menu[5].command == .custom("h2"))
    }

    @Test("fehlen quit oder configs, hängt die Shell sie unter ApolloShell an")
    func requiredEntries() {
        let spec = CommandCenterSpec(entries: [.item(MenuItemSpec(title: "Hello", handler: "h"))])
        let menu = CommandCenterModel.build(spec, state: Self.state())
        #expect(Self.titles(menu) == ["Hello", "---", "ApolloShell", "Config", "Quit ApolloShell"])
        #expect(menu[2].kind == .header)
        let onlyQuit = CommandCenterModel.build(CommandCenterSpec(entries: [.builtin("quit")]), state: Self.state())
        #expect(Self.titles(onlyQuit) == ["Quit ApolloShell", "---", "ApolloShell", "Config"])
        let nested = CommandCenterModel.build(CommandCenterSpec(entries: [.submenu(title: "More", entries: [.builtin("configs"), .builtin("quit")])]), state: Self.state())
        #expect(Self.titles(nested) == ["More"])
        let empty = CommandCenterModel.build(CommandCenterSpec(entries: []), state: Self.state())
        #expect(Self.titles(empty) == ["ApolloShell", "Config", "Quit ApolloShell"])
    }

    @Test("Trennlinien doppeln sich nicht und stehen nicht am Rand")
    func separators() {
        let spec = CommandCenterSpec(entries: [.separator, .builtin("problems"), .separator, .separator, .builtin("quit"), .builtin("configs"), .separator])
        let menu = CommandCenterModel.build(spec, state: Self.state())
        #expect(Self.titles(menu) == ["Quit ApolloShell", "Config"])
    }

    @Test("eigene Einträge: checked, disabled, icon und Untermenü")
    func customItemProperties() throws {
        let spec = CommandCenterSpec(entries: [
            .submenu(title: "Tools", entries: [.item(MenuItemSpec(title: "A", icon: "star", checked: true, disabled: true, handler: "a"))]),
            .builtin("configs"), .builtin("quit"),
        ])
        let menu = CommandCenterModel.build(spec, state: Self.state())
        let item = try #require(menu[0].children?.first)
        #expect(item.checked && !item.enabled)
        #expect(item.icon == "star")
    }

    @Test("visible=false versteckt nur das Symbol")
    func hiddenIcon() {
        let spec = CommandCenterSpec(visible: false, entries: nil)
        #expect(!spec.visible)
        #expect(CommandCenterModel.build(spec, state: Self.state()).count == 13)
    }
}
