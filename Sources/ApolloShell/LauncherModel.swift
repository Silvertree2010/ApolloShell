import AppKit
import ApolloShellCore
import Observation

/// State of the list: search text, sorted apps, selection.
@MainActor
@Observable
final class LauncherModel {
    var query = "" {
        didSet {
            armed = nil
            applyFilter()
        }
    }
    private(set) var results: [LauncherRow] = []
    /// An action that asks first (log out, restart, shut down) and was chosen
    /// once: the next Return or click runs it. Any typing disarms it.
    var armed: LauncherAction?
    var selectedIndex = 0
    /// Counts up on every opening, so the view refocuses the search field
    /// (onAppear only runs once, the panel stays alive).
    private(set) var openCount = 0

    /// Set from outside: act on a row (start an app, run an action) or
    /// close the launcher.
    @ObservationIgnored var onActivate: (LauncherRow) -> Void = { _ in }
    @ObservationIgnored var onClose: () -> Void = {}
    /// Right-click on a row: the controller builds the menu (the app's own,
    /// see `AppleDockMenu`) and opens it at this view.
    @ObservationIgnored var onRightClick: (AppEntry, NSView) -> Void = { _, _ in }
    /// A pinned row dropped onto another pinned row (bundle IDs).
    @ObservationIgnored var onMovePin: (String, String) -> Void = { _, _ in }

    @ObservationIgnored private var all: [AppEntry] = []
    @ObservationIgnored private var usage = UsageStats()
    private(set) var pinned: [String] = []
    @ObservationIgnored private let ranker = AppRanker()
    @ObservationIgnored private var iconCache: [URL: NSImage] = [:]
    /// The themes for `>theme`: identifier (`nil` = none), title, current.
    @ObservationIgnored var themes: () -> [(id: String?, title: String, current: Bool)] = { [] }
    /// Read once per opening, and only when `>wallpaper` asks for them.
    @ObservationIgnored private var wallpapers: [AppleWallpaper]?

    var selected: LauncherRow? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    func reload(_ apps: [AppEntry], usage: UsageStats, pinned: [String]) {
        all = apps
        self.usage = usage
        self.pinned = pinned
        wallpapers = nil
        query = ""
        applyFilter()
        openCount += 1
    }

    /// The pins changed (right click, dragging): sort anew, but keep the
    /// search text and the selected app.
    func setPinned(_ ids: [String]) {
        let selectedID = selected?.id
        pinned = ids
        results = rows(for: query)
        selectedIndex = results.firstIndex { $0.id == selectedID } ?? 0
    }

    func isPinned(_ app: AppEntry) -> Bool {
        app.bundleID.map(pinned.contains) ?? false
    }

    /// Pins can only be dragged while they stand on top as a block - with
    /// search text the order is the one of the hits.
    func canDragPin(_ app: AppEntry) -> Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty && isPinned(app)
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), results.count - 1)
    }

    func launchSelected() {
        if let row = selected { onActivate(row) }
    }

    func icon(for app: AppEntry) -> NSImage {
        if let cached = iconCache[app.url] { return cached }
        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        iconCache[app.url] = image
        return image
    }

    private func applyFilter() {
        results = rows(for: query)
        selectedIndex = 0
    }

    /// Apps without a prefix; after `>` the action mode (`LauncherQuery`).
    private func rows(for text: String) -> [LauncherRow] {
        switch LauncherQuery.parse(text) {
        case .apps(let query):
            return ranker.rank(all, query: query, usage: usage, pinned: pinned).map(LauncherRow.app)
        case .actions(let filter):
            return LauncherAction.matching(filter).map(LauncherRow.action)
        case .calculator(let expression):
            guard !expression.isEmpty else { return [.note(String(localized: "Type a sum, like 2*(3+4)"))] }
            guard let value = LauncherCalculator.evaluate(expression) else {
                return [.note(String(localized: "Not a complete sum yet"))]
            }
            return [.calculation(result: LauncherCalculator.format(value))]
        case .theme(let filter):
            let needle = filter.lowercased()
            return themes()
                .filter { needle.isEmpty || $0.title.lowercased().contains(needle) }
                .map { LauncherRow.theme(id: $0.id, title: $0.title, current: $0.current) }
        case .wallpaper(let filter):
            if wallpapers == nil { wallpapers = AppleWallpaper.all() }
            let needle = filter.lowercased()
            return (wallpapers ?? [])
                .filter { needle.isEmpty || $0.name.lowercased().contains(needle) }
                .map(LauncherRow.wallpaper)
        }
    }

    /// A preview of a wallpaper, small and cached like the app icons.
    func thumbnail(for wallpaper: AppleWallpaper) -> NSImage? {
        guard let url = wallpaper.thumbnail else { return nil }
        if let cached = iconCache[url] { return cached }
        let image = NSImage(contentsOf: url)
        iconCache[url] = image
        return image
    }
}
