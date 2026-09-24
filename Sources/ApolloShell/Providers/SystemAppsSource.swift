import AppKit
import ApolloProviders
import ApolloShellCore
import os

@MainActor
final class SystemAppsSource: AppsSource {
    private static let dockDomain = "com.apple.dock" as CFString
    private static let persistentApps = "persistent-apps" as CFString

    private let directory: URL
    private let ownBundleID = Bundle.main.bundleIdentifier
    private let log = Logger(category: "apps")
    private var observers: [NSObjectProtocol] = []

    init(directory: URL) {
        self.directory = directory
    }

    private var usageURL: URL { directory.appendingPathComponent("usage.json") }
    private var favoritesURL: URL { directory.appendingPathComponent("pinned.json") }

    var now: Date { Date() }

    var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    var systemFileViewer: String? { UserDefaults.standard.string(forKey: "NSFileViewer") }

    func scanCatalog(_ completion: @escaping @MainActor ([AppEntry]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let entries = AppCatalog().scan()
            Task { @MainActor in completion(entries) }
        }
    }

    func runningApps() -> [RunningApp] {
        let windows = Self.windowCounts()
        var seen: Set<String> = []
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier, id != ownBundleID, seen.insert(id).inserted else { return nil }
            return RunningApp(
                bundleID: id,
                name: app.localizedName ?? id,
                path: app.bundleURL?.path,
                active: app.isActive,
                hidden: app.isHidden,
                launching: !app.isFinishedLaunching,
                windows: windows[app.processIdentifier] ?? 0,
                minimized: 0
            )
        }
    }

    func dockPinned() -> [String] {
        CFPreferencesAppSynchronize(Self.dockDomain)
        let tiles = CFPreferencesCopyAppValue(Self.persistentApps, Self.dockDomain) as? [Any] ?? []
        return tiles.compactMap(AppleDockPrefs.bundleID(ofTile:))
    }

    func placeInDock(_ bundleID: String, at position: AppleDockPrefs.Position) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let label = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        writeTiles {
            AppleDockPrefs.placing(bundleID, at: position, in: $0) {
                AppleDockPrefs.tile(bundleID: bundleID, url: url, label: label, guid: Int.random(in: 1...Int(Int32.max)))
            }
        }
        return true
    }

    func removeFromDock(_ bundleID: String) -> Bool {
        writeTiles { AppleDockPrefs.removing(bundleID, from: $0) }
        return true
    }

    private func writeTiles(_ change: ([Any]) -> [Any]) {
        CFPreferencesAppSynchronize(Self.dockDomain)
        let tiles = CFPreferencesCopyAppValue(Self.persistentApps, Self.dockDomain) as? [Any] ?? []
        CFPreferencesSetAppValue(Self.persistentApps, change(tiles) as NSArray as CFArray, Self.dockDomain)
        CFPreferencesAppSynchronize(Self.dockDomain)
    }

    func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    func appName(_ bundleID: String) -> String? {
        appPath(bundleID).map { FileManager.default.displayName(atPath: $0).replacingOccurrences(of: ".app", with: "") }
    }

    func appPath(_ bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
    }

    func readBadges(_ completion: @escaping @MainActor ([String: String]) -> Void) {
        Task { @MainActor in
            completion(await DockBadges.readOffMain())
        }
    }

    func loadUsage() -> Data? { try? Data(contentsOf: usageURL) }

    func saveUsage(_ data: Data) -> Bool { write(data, to: usageURL) }

    func loadFavorites() -> Data? { try? Data(contentsOf: favoritesURL) }

    func saveFavorites(_ data: Data) -> Bool { write(data, to: favoritesURL) }

    func preserveUnreadableFavorites() {
        let copy = favoritesURL.appendingPathExtension("unreadable")
        try? FileManager.default.removeItem(at: copy)
        try? FileManager.default.copyItem(at: favoritesURL, to: copy)
    }

    private func write(_ data: Data, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            log.error("\(url.lastPathComponent, privacy: .public) nicht gespeichert: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func observeChanges(_ handler: @escaping @MainActor (AppsChange) -> Void) {
        stopObserving()
        let center = NSWorkspace.shared.notificationCenter
        let mapping: [(Notification.Name, (String) -> AppsChange)] = [
            (NSWorkspace.didLaunchApplicationNotification, { .launched($0) }),
            (NSWorkspace.didTerminateApplicationNotification, { .terminated($0) }),
            (NSWorkspace.didActivateApplicationNotification, { .activated($0) }),
            (NSWorkspace.didHideApplicationNotification, { _ in .visibility }),
            (NSWorkspace.didUnhideApplicationNotification, { _ in .visibility }),
        ]
        let own = ownBundleID
        for (name, change) in mapping {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let app, app.activationPolicy == .regular, let id = app.bundleIdentifier, id != own else { return }
                let value = change(id)
                MainActor.assumeIsolated { handler(value) }
            })
        }
    }

    func stopObserving() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    func clickState(_ bundleID: String, command: Bool, option: Bool) -> DockClickState {
        let app = runningApp(bundleID)
        let windows = app.map { DockWindows.list(pid: $0.processIdentifier) } ?? []
        let visible = windows.filter { !$0.minimized }
        let onScreen = app.map { DockWindows.onScreenWindowIDs(pid: $0.processIdentifier) } ?? []
        let onActiveSpace = visible.filter { $0.windowID.map(onScreen.contains) ?? false }
        let minimizedIDs = Set(windows.filter(\.minimized).compactMap(\.windowID))
        let elsewhere = app.map {
            DockWindows.allWindowIDs(pid: $0.processIdentifier, requireSpace: !$0.isHidden)
                .subtracting(onScreen)
                .subtracting(minimizedIDs)
                .count
        } ?? 0
        let frontmost = app != nil && app?.processIdentifier == NSWorkspace.shared.frontmostApplication?.processIdentifier
        let covered = (frontmost && !onActiveSpace.isEmpty) ? app.flatMap { DockWindows.coveredWindowID(pid: $0.processIdentifier) } : nil
        return DockClickState(
            running: app != nil,
            frontmost: frontmost,
            hidden: app?.isHidden ?? false,
            windowsOnActiveSpace: onActiveSpace.count,
            windowsElsewhere: elsewhere,
            minimizedWindows: windows.count(where: \.minimized),
            hasCoveredWindow: covered != nil,
            command: command,
            option: option
        )
    }

    func launch(_ bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [log] _, error in
            if let error {
                log.error("Start fehlgeschlagen: \((error as NSError).code, privacy: .public)")
            }
        }
        return true
    }

    func perform(_ action: AppsWindowAction, on bundleID: String) -> Bool {
        let app = runningApp(bundleID)
        switch action {
        case .click(let step, let previous):
            return click(step, app: app, previous: previous)
        case .newWindow:
            guard let app, let command = DockAppCommands.commands(pid: app.processIdentifier).first(where: { $0.kind == .newItem }) else { return false }
            DockAppCommands.press(command, of: app)
            return true
        case .cycleWindows:
            guard let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == bundleID else { return false }
            let windows = DockWindows.list(pid: front.processIdentifier).filter { !$0.minimized }
            guard let index = DockWindowCycle.indexToRaise(isFrontmost: true, visibleWindows: windows.count) else { return false }
            DockWindows.raise(windows[index], of: front)
            return true
        case .showAllWindows:
            guard let app else { return false }
            SpaceSwitcher.showAppWindows(of: app)
            return true
        case .openFiles(let paths):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open(paths.map { URL(fileURLWithPath: $0) }, withApplicationAt: url, configuration: configuration) { [log] _, error in
                if let error {
                    log.error("Dateien nicht geoeffnet: \((error as NSError).code, privacy: .public)")
                }
            }
            return true
        case .hide:
            return app?.hide() ?? false
        case .unhide:
            return app?.unhide() ?? false
        case .quit:
            return app?.terminate() ?? false
        case .forceQuit:
            return app?.forceTerminate() ?? false
        }
    }

    private func click(_ step: DockClickAction, app: NSRunningApplication?, previous: String?) -> Bool {
        guard let app else { return false }
        switch step {
        case .unhide:
            return app.unhide()
        case .activate:
            return app.activate()
        case .raiseWindowElsewhere:
            let onScreen = DockWindows.onScreenWindowIDs(pid: app.processIdentifier)
            if let window = DockWindows.list(pid: app.processIdentifier, allSpaces: true).first(where: { !$0.minimized && !($0.windowID.map(onScreen.contains) ?? false) }) {
                DockWindows.raise(window, of: app)
            } else {
                app.activate()
            }
            return true
        case .raiseWindowOnActiveSpace:
            let onScreen = DockWindows.onScreenWindowIDs(pid: app.processIdentifier)
            guard let window = DockWindows.list(pid: app.processIdentifier).first(where: { !$0.minimized && ($0.windowID.map(onScreen.contains) ?? false) }) else { return false }
            DockWindows.raise(window, of: app)
            return true
        case .raiseCoveredWindow:
            guard let covered = DockWindows.coveredWindowID(pid: app.processIdentifier),
                  let window = DockWindows.list(pid: app.processIdentifier).first(where: { $0.windowID == covered })
            else { return false }
            DockWindows.raise(window, of: app)
            return true
        case .unminimizeLast:
            guard let window = DockWindows.list(pid: app.processIdentifier).first(where: \.minimized) else { return false }
            DockWindows.raise(window, of: app)
            return true
        case .newWindow:
            return perform(.newWindow, on: app.bundleIdentifier ?? "")
        case .hidePrevious:
            guard let previous, previous != app.bundleIdentifier, previous != ownBundleID,
                  let other = runningApp(previous)
            else { return false }
            return other.hide()
        case .launch, .reveal:
            return false
        }
    }

    func reveal(_ bundleID: String, _ how: AppsReveal) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        switch how {
        case .finder, .fileManager(.selectInFileViewer):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .fileManager(.openFolder(let id)):
            guard let manager = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([url.deletingLastPathComponent()], withApplicationAt: manager, configuration: configuration) { [log] _, error in
                if let error {
                    log.error("Ordner nicht gezeigt: \((error as NSError).code, privacy: .public)")
                }
            }
        }
    }

    func runMenuCommand(_ bundleID: String, _ command: String) -> Bool {
        guard let app = runningApp(bundleID),
              let item = DockAppCommands.commands(pid: app.processIdentifier).first(where: { $0.title == command })
        else { return false }
        DockAppCommands.press(item, of: app)
        return true
    }

    private func runningApp(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    private static func windowCounts() -> [pid_t: Int] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var counts: [pid_t: Int] = [:]
        for entry in info {
            guard let owner = entry[kCGWindowOwnerPID as String] as? Int,
                  (entry[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double,
                  width >= 100, height >= 100
            else { continue }
            counts[pid_t(owner), default: 0] += 1
        }
        return counts
    }
}
