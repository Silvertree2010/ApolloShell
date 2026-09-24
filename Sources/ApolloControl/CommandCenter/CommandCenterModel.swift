import Foundation
import ApolloShellCore

public enum CommandCenterModel {
    public static let builtinNames = [
        "reload-config", "restart", "problems", "configs", "themes", "marketplace",
        "updates", "crash-reports", "login-item", "install-cli", "about", "quit",
    ]

    static let defaultEntries: [CommandCenterEntry] = [
        .builtin("reload-config"), .builtin("restart"), .builtin("problems"),
        .separator,
        .builtin("configs"), .builtin("themes"), .builtin("marketplace"),
        .separator,
        .builtin("updates"), .builtin("crash-reports"), .builtin("login-item"), .builtin("install-cli"),
        .separator,
        .builtin("about"), .builtin("quit"),
    ]

    static let required = ["configs", "quit"]

    public static func build(_ spec: CommandCenterSpec?, state: CommandCenterState) -> [MenuEntry] {
        guard let custom = spec?.entries else {
            return tidy(expand(defaultEntries, state: state))
        }
        var entries = expand(custom, state: state)
        let present = builtins(in: custom)
        let missing = required.filter { !present.contains($0) }
        if !missing.isEmpty {
            entries.append(.separator)
            entries.append(.header("ApolloShell"))
            entries += expand(missing.map(CommandCenterEntry.builtin), state: state)
        }
        return tidy(entries)
    }

    static func builtins(in entries: [CommandCenterEntry]) -> Set<String> {
        var names: Set<String> = []
        for entry in entries {
            switch entry {
            case .builtin(let name): names.insert(name)
            case .submenu(_, let children): names.formUnion(builtins(in: children))
            case .item, .separator: break
            }
        }
        return names
    }

    static func expand(_ entries: [CommandCenterEntry], state: CommandCenterState) -> [MenuEntry] {
        entries.flatMap { entry -> [MenuEntry] in
            switch entry {
            case .builtin(let name):
                return builtin(name, state: state)
            case .item(let item):
                return [MenuEntry(title: item.title, shortcut: item.shortcut, icon: item.icon, checked: item.checked, enabled: !item.disabled, command: .custom(item.handler))]
            case .separator:
                return [.separator]
            case .submenu(let title, let children):
                return [MenuEntry(title: title, children: tidy(expand(children, state: state)))]
            }
        }
    }

    static func tidy(_ entries: [MenuEntry]) -> [MenuEntry] {
        var result: [MenuEntry] = []
        for entry in entries {
            if entry.kind == .separator, result.isEmpty || result.last?.kind == .separator {
                continue
            }
            result.append(entry)
        }
        while result.last?.kind == .separator {
            result.removeLast()
        }
        return result
    }

    static func builtin(_ name: String, state: CommandCenterState) -> [MenuEntry] {
        switch name {
        case "reload-config":
            return [MenuEntry(title: "Reload Config", shortcut: "cmd+r", command: .reloadConfig)]
        case "restart":
            return [MenuEntry(title: "Restart ApolloShell", command: .restart)]
        case "problems":
            return state.problemCount > 0 ? [MenuEntry(title: "Show Problems (\(state.problemCount))", command: .showProblems)] : []
        case "configs":
            return [MenuEntry(title: "Config", children: configs(state))]
        case "themes":
            return [MenuEntry(title: "Theme", children: themes(state))]
        case "marketplace":
            return state.marketplaceEnabled ? [MenuEntry(title: "Marketplace…", command: .openMarketplace)] : []
        case "updates":
            return [MenuEntry(title: "Updates", children: updates(state))]
        case "crash-reports":
            return [MenuEntry(title: "Crash Reports", children: [
                MenuEntry(title: "Ask", checked: state.crashReports == .ask, command: .crashReports(.ask)),
                MenuEntry(title: "Always Send", checked: state.crashReports == .always, command: .crashReports(.always)),
                MenuEntry(title: "Never Send", checked: state.crashReports == .never, command: .crashReports(.never)),
            ])]
        case "login-item":
            return [MenuEntry(title: "Start at Login", checked: state.startsAtLogin, command: .setStartAtLogin(!state.startsAtLogin))]
        case "install-cli":
            return state.installKind == .disk && !state.cliInstalled ? [MenuEntry(title: "Install Command Line Tool…", command: .installCommandLineTool)] : []
        case "about":
            return [MenuEntry(title: "About ApolloShell", command: .about)]
        case "quit":
            return [MenuEntry(title: "Quit ApolloShell", shortcut: "cmd+q", command: .quit)]
        default:
            return []
        }
    }

    static func configs(_ state: CommandCenterState) -> [MenuEntry] {
        state.configs.map { MenuEntry(title: $0.id, checked: $0.isActive, command: .selectConfig($0.id)) } + [
            .separator,
            MenuEntry(title: "Open Config Folder", command: .openConfigFolder),
            MenuEntry(title: "Copy to Own Config…", command: .copyToOwnConfig),
        ]
    }

    static func themes(_ state: CommandCenterState) -> [MenuEntry] {
        var entries = [MenuEntry(title: "None", checked: !state.themes.contains { $0.isActive }, command: .selectTheme(nil))]
        entries += state.themes.map { MenuEntry(title: $0.id, checked: $0.isActive, command: .selectTheme($0.id)) }
        entries.append(.separator)
        if let active = state.themes.first(where: { $0.isActive }), active.issueCount > 0 {
            entries.append(MenuEntry(title: "Show Theme Issues (\(active.issueCount))", command: .showThemeIssues(active.id)))
        }
        entries.append(MenuEntry(title: "Add Theme…", command: .addTheme))
        entries.append(MenuEntry(title: "Open Themes Folder", command: .openThemesFolder))
        return entries
    }

    static func updates(_ state: CommandCenterState) -> [MenuEntry] {
        var entries = [MenuEntry.status(statusLine(state))]
        if case .ready(let version) = state.update {
            entries.append(MenuEntry(title: "Restart to Install \(version)", command: .installUpdate))
        }
        if let notes = state.releaseNotes {
            entries.append(MenuEntry(title: "Release Notes", command: .releaseNotes(notes)))
        }
        entries.append(.separator)
        entries.append(MenuEntry(title: "Check for Updates…", command: .checkForUpdates))
        entries.append(MenuEntry(title: "Check Automatically", checked: state.autoCheck, command: .setAutoCheck(!state.autoCheck)))
        switch state.installKind {
        case .disk:
            entries.append(MenuEntry(title: "Install Automatically", checked: state.autoInstall, command: .setAutoInstall(!state.autoInstall)))
        case .homebrew:
            entries.append(MenuEntry(title: "Copy \(InstallKind.homebrewUpgradeCommand)", command: .copyBrewUpgrade))
        }
        return entries
    }

    static func statusLine(_ state: CommandCenterState) -> String {
        let time = state.lastUpdateCheck.map { clock($0, timeZone: state.timeZone) }
        switch state.update {
        case .idle: return time.map { "Last Checked \($0)" } ?? "Not Checked Yet"
        case .checking: return "Checking…"
        case .upToDate: return time.map { "Up to Date · checked \($0)" } ?? "Up to Date"
        case .available(let version), .ready(let version): return "Version \(version) Available"
        case .failed(let message): return "Failed: \(message)"
        case .unavailable: return "This Build Cannot Update Itself"
        }
    }

    static func clock(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
