import Foundation
import ApolloRuntime
import ApolloShellCore
@testable import ApolloProviders

@MainActor
final class FakeAppsSource: AppsSource {
    let clock: ManualRuntimeClock
    let base = Date(timeIntervalSince1970: 1_790_000_000)
    var accessibilityTrusted = true
    var systemFileViewer: String?
    var catalog = [
        AppEntry(name: "Finder", url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), bundleID: "com.apple.finder"),
        AppEntry(name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"), bundleID: "com.apple.Safari"),
        AppEntry(name: "Mail", url: URL(fileURLWithPath: "/System/Applications/Mail.app"), bundleID: "com.apple.mail"),
        AppEntry(name: "Notes", url: URL(fileURLWithPath: "/System/Applications/Notes.app"), bundleID: "com.apple.Notes"),
        AppEntry(name: "ForkLift", url: URL(fileURLWithPath: "/Applications/ForkLift.app"), bundleID: "com.binarynights.ForkLift"),
    ]
    var running = [
        RunningApp(bundleID: "com.apple.finder", name: "Finder", windows: 1),
        RunningApp(bundleID: "com.apple.Safari", name: "Safari", active: true, windows: 2),
        RunningApp(bundleID: "com.apple.Notes", name: "Notes", hidden: true, windows: 1, minimized: 1),
    ]
    var pinned = ["com.apple.Safari", "com.apple.mail"]
    var badges = ["com.apple.mail": "3"]
    var usageData: Data?
    var favoritesData: Data? = PinnedList(["com.apple.mail", "org.gone.App"]).encoded()
    var preservedUnreadable = 0
    var scans = 0
    var badgeReads = 0
    var observing = false
    var launches: [String] = []
    var performed: [(AppsWindowAction, String)] = []
    var revealed: [(String, AppsReveal)] = []
    var placed: [(String, AppleDockPrefs.Position)] = []
    var removed: [String] = []
    var commands: [(String, String)] = []
    var clickStates: [String: DockClickState] = [:]
    private var handler: (@MainActor (AppsChange) -> Void)?

    init(clock: ManualRuntimeClock) {
        self.clock = clock
    }

    var now: Date { base.addingTimeInterval(clock.now) }

    func scanCatalog(_ completion: @escaping @MainActor ([AppEntry]) -> Void) {
        scans += 1
        completion(catalog)
    }

    func runningApps() -> [RunningApp] { running }

    func dockPinned() -> [String] { pinned }

    func placeInDock(_ bundleID: String, at position: AppleDockPrefs.Position) -> Bool {
        placed.append((bundleID, position))
        return true
    }

    func removeFromDock(_ bundleID: String) -> Bool {
        removed.append(bundleID)
        pinned.removeAll { $0 == bundleID }
        return true
    }

    func isInstalled(_ bundleID: String) -> Bool {
        catalog.contains { $0.bundleID == bundleID }
    }

    func appName(_ bundleID: String) -> String? {
        catalog.first { $0.bundleID == bundleID }?.name
    }

    func appPath(_ bundleID: String) -> String? {
        catalog.first { $0.bundleID == bundleID }?.url.path
    }

    func readBadges(_ completion: @escaping @MainActor ([String: String]) -> Void) {
        badgeReads += 1
        completion(badges)
    }

    func loadUsage() -> Data? { usageData }

    var savesFail = false

    func saveUsage(_ data: Data) -> Bool {
        guard !savesFail else { return false }
        usageData = data
        return true
    }

    func loadFavorites() -> Data? { favoritesData }

    func saveFavorites(_ data: Data) -> Bool {
        guard !savesFail else { return false }
        favoritesData = data
        return true
    }

    func preserveUnreadableFavorites() { preservedUnreadable += 1 }

    func observeChanges(_ handler: @escaping @MainActor (AppsChange) -> Void) {
        observing = true
        self.handler = handler
    }

    func stopObserving() {
        observing = false
        handler = nil
    }

    func send(_ change: AppsChange) {
        handler?(change)
    }

    func clickState(_ bundleID: String, command: Bool, option: Bool) -> DockClickState {
        let app = running.first { $0.bundleID == bundleID }
        let base = clickStates[bundleID] ?? DockClickState(
            running: app != nil, frontmost: app?.active ?? false, hidden: app?.hidden ?? false,
            windowsOnActiveSpace: app?.windows ?? 0, windowsElsewhere: 0, minimizedWindows: app?.minimized ?? 0,
            command: false, option: false
        )
        return DockClickState(
            running: base.running, launching: base.launching, frontmost: base.frontmost, hidden: base.hidden,
            windowsOnActiveSpace: base.windowsOnActiveSpace, windowsElsewhere: base.windowsElsewhere,
            minimizedWindows: base.minimizedWindows, hasCoveredWindow: base.hasCoveredWindow,
            command: command, option: option
        )
    }

    func launch(_ bundleID: String) -> Bool {
        launches.append(bundleID)
        return isInstalled(bundleID)
    }

    var cycles = true

    func perform(_ action: AppsWindowAction, on bundleID: String) -> Bool {
        performed.append((action, bundleID))
        if case .cycleWindows = action { return cycles }
        return true
    }

    func reveal(_ bundleID: String, _ how: AppsReveal) {
        revealed.append((bundleID, how))
    }

    func runMenuCommand(_ bundleID: String, _ command: String) -> Bool {
        commands.append((bundleID, command))
        return true
    }
}
