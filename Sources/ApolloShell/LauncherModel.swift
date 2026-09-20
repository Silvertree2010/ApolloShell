import AppKit
import ApolloShellCore
import Observation

/// State of the list: search text, sorted apps, selection.
@MainActor
@Observable
final class LauncherModel {
    var query = "" {
        didSet { applyFilter() }
    }
    private(set) var results: [AppEntry] = []
    var selectedIndex = 0
    /// Counts up on every opening, so the view refocuses the search field
    /// (onAppear only runs once, the panel stays alive).
    private(set) var openCount = 0

    /// Set from outside: launch app or close the launcher.
    @ObservationIgnored var onLaunch: (AppEntry) -> Void = { _ in }
    @ObservationIgnored var onClose: () -> Void = {}
    /// Right-click on a row: the controller builds the menu (the app's own,
    /// see `AppleDockMenu`) and opens it at this view.
    @ObservationIgnored var onRightClick: (AppEntry, NSView) -> Void = { _, _ in }

    @ObservationIgnored private var all: [AppEntry] = []
    @ObservationIgnored private var usage = UsageStats()
    @ObservationIgnored private var pinned: [String] = []
    @ObservationIgnored private let ranker = AppRanker()
    @ObservationIgnored private var iconCache: [URL: NSImage] = [:]

    var selected: AppEntry? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    func reload(_ apps: [AppEntry], usage: UsageStats, pinned: [String]) {
        all = apps
        self.usage = usage
        self.pinned = pinned
        query = ""
        applyFilter()
        openCount += 1
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), results.count - 1)
    }

    func launchSelected() {
        if let app = selected { onLaunch(app) }
    }

    func icon(for app: AppEntry) -> NSImage {
        if let cached = iconCache[app.url] { return cached }
        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        iconCache[app.url] = image
        return image
    }

    private func applyFilter() {
        results = ranker.rank(all, query: query, usage: usage, pinned: pinned)
        selectedIndex = 0
    }
}
