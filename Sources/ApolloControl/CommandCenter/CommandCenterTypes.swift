import Foundation
import ApolloShellCore

public enum UpdateStatus: Sendable, Hashable {
    case idle
    case checking
    case upToDate
    case available(version: String)
    case ready(version: String)
    case failed(String)
    case unavailable
}

public struct CommandCenterState: Sendable, Hashable {
    public struct Config: Sendable, Hashable {
        public var id: String
        public var isActive: Bool

        public init(id: String, isActive: Bool) {
            self.id = id
            self.isActive = isActive
        }
    }

    public struct Theme: Sendable, Hashable {
        public var id: String
        public var issueCount: Int
        public var isActive: Bool

        public init(id: String, issueCount: Int, isActive: Bool) {
            self.id = id
            self.issueCount = issueCount
            self.isActive = isActive
        }
    }

    public var problemCount = 0
    public var configs: [Config]
    public var themes: [Theme]
    public var marketplaceEnabled = false
    public var update = UpdateStatus.idle
    public var lastUpdateCheck: Date?
    public var releaseNotes: URL?
    public var installKind = InstallKind.disk
    public var autoCheck = true
    public var autoInstall = true
    public var crashReports = CrashReportSettings.Mode.ask
    public var startsAtLogin = false
    public var cliInstalled = false
    public var timeZone: TimeZone

    public init(configs: [Config], themes: [Theme], timeZone: TimeZone = .current) {
        self.configs = configs
        self.themes = themes
        self.timeZone = timeZone
    }
}

public enum MenuCommand: Sendable, Hashable {
    case reloadConfig
    case restart
    case showProblems
    case selectConfig(String)
    case openConfigFolder
    case copyToOwnConfig
    case selectTheme(String?)
    case showThemeIssues(String)
    case addTheme
    case openThemesFolder
    case openMarketplace
    case installUpdate
    case releaseNotes(URL)
    case checkForUpdates
    case setAutoCheck(Bool)
    case setAutoInstall(Bool)
    case copyBrewUpgrade
    case crashReports(CrashReportSettings.Mode)
    case setStartAtLogin(Bool)
    case installCommandLineTool
    case about
    case quit
    case custom(String)
}

public struct MenuEntry: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case item, separator, header
    }

    public var kind: Kind
    public var title: String
    public var shortcut: String?
    public var icon: String?
    public var checked: Bool
    public var enabled: Bool
    public var command: MenuCommand?
    public var children: [MenuEntry]?

    public init(kind: Kind = .item, title: String, shortcut: String? = nil, icon: String? = nil, checked: Bool = false, enabled: Bool = true, command: MenuCommand? = nil, children: [MenuEntry]? = nil) {
        self.kind = kind
        self.title = title
        self.shortcut = shortcut
        self.icon = icon
        self.checked = checked
        self.enabled = enabled
        self.command = command
        self.children = children
    }

    public static let separator = MenuEntry(kind: .separator, title: "")

    public static func header(_ title: String) -> MenuEntry {
        MenuEntry(kind: .header, title: title, enabled: false)
    }

    public static func status(_ title: String) -> MenuEntry {
        MenuEntry(title: title, enabled: false)
    }
}

public struct MenuItemSpec: Sendable, Hashable {
    public var title: String
    public var icon: String?
    public var shortcut: String?
    public var checked: Bool
    public var disabled: Bool
    public var handler: String

    public init(title: String, icon: String? = nil, shortcut: String? = nil, checked: Bool = false, disabled: Bool = false, handler: String) {
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
        self.checked = checked
        self.disabled = disabled
        self.handler = handler
    }
}

public indirect enum CommandCenterEntry: Sendable, Hashable {
    case builtin(String)
    case item(MenuItemSpec)
    case separator
    case submenu(title: String, entries: [CommandCenterEntry])
}

public struct CommandCenterSpec: Sendable, Hashable {
    public var visible: Bool
    public var entries: [CommandCenterEntry]?

    public init(visible: Bool = true, entries: [CommandCenterEntry]? = nil) {
        self.visible = visible
        self.entries = entries
    }
}
