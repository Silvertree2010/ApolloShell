import Foundation
import ApolloShellCore

public struct RunningApp: Equatable, Sendable {
    public var bundleID: String
    public var name: String
    public var path: String?
    public var active: Bool
    public var hidden: Bool
    public var launching: Bool
    public var windows: Int
    public var minimized: Int

    public init(bundleID: String, name: String, path: String? = nil, active: Bool = false, hidden: Bool = false, launching: Bool = false, windows: Int = 0, minimized: Int = 0) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
        self.active = active
        self.hidden = hidden
        self.launching = launching
        self.windows = windows
        self.minimized = minimized
    }
}

public enum AppsChange: Equatable, Sendable {
    case launched(String)
    case terminated(String)
    case activated(String)
    case visibility
    case dock
}

public enum AppsWindowAction: Equatable, Sendable {
    case click(DockClickAction, previous: String?)
    case newWindow
    case cycleWindows(up: Bool)
    case showAllWindows
    case openFiles([String])
    case hide
    case unhide
    case quit
    case forceQuit
}

public enum AppsReveal: Equatable, Sendable {
    case finder
    case fileManager(ProviderFileManager.Reveal)
}

@MainActor
public protocol AppsSource: AnyObject {
    var now: Date { get }
    var accessibilityTrusted: Bool { get }
    var systemFileViewer: String? { get }
    func scanCatalog(_ completion: @escaping @MainActor ([AppEntry]) -> Void)
    func runningApps() -> [RunningApp]
    func dockPinned() -> [String]
    func placeInDock(_ bundleID: String, at position: AppleDockPrefs.Position) -> Bool
    func removeFromDock(_ bundleID: String) -> Bool
    func isInstalled(_ bundleID: String) -> Bool
    func appName(_ bundleID: String) -> String?
    func appPath(_ bundleID: String) -> String?
    func readBadges(_ completion: @escaping @MainActor ([String: String]) -> Void)
    func loadUsage() -> Data?
    func saveUsage(_ data: Data) -> Bool
    func loadFavorites() -> Data?
    func saveFavorites(_ data: Data) -> Bool
    func preserveUnreadableFavorites()
    func observeChanges(_ handler: @escaping @MainActor (AppsChange) -> Void)
    func stopObserving()
    func clickState(_ bundleID: String, command: Bool, option: Bool) -> DockClickState
    func launch(_ bundleID: String) -> Bool
    func perform(_ action: AppsWindowAction, on bundleID: String) -> Bool
    func reveal(_ bundleID: String, _ how: AppsReveal)
    func runMenuCommand(_ bundleID: String, _ command: String) -> Bool
}
