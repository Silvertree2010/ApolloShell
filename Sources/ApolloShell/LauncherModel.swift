import AppKit
import ApolloShellCore
import Observation

@MainActor
@Observable
final class LauncherModel {
    var query = "" {
        didSet { applyFilter() }
    }
    private(set) var results: [LauncherItem] = []
    var selectedIndex = 0
    private(set) var openCount = 0

    @ObservationIgnored var onActivate: (LauncherItem) -> Void = { _ in }
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored var onRightClick: (AppEntry, NSView) -> Void = { _, _ in }

    @ObservationIgnored private var all: [AppEntry] = []
    @ObservationIgnored private var usage = UsageStats()
    @ObservationIgnored private var pinned: [String] = []
    @ObservationIgnored private let ranker = AppRanker()
    @ObservationIgnored private var iconCache: [URL: NSImage] = [:]
    @ObservationIgnored private var files: [URL] = []
    @ObservationIgnored private let search = LauncherFileSearch()
    @ObservationIgnored let clips: ClipboardHistory

    init(clips: ClipboardHistory = .shared) {
        self.clips = clips
        search.onResults = { [weak self] r in
            guard let self else { return }
            self.files = r
            self.applyFilter(keep: true)
        }
    }

    var selected: LauncherItem? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    func reload(_ apps: [AppEntry], usage: UsageStats, pinned: [String]) {
        all = apps
        self.usage = usage
        self.pinned = pinned
        files = []
        query = ""
        applyFilter()
        openCount += 1
    }

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        var i = selectedIndex
        repeat {
            i += delta
        } while results.indices.contains(i) && !results[i].selectable
        if results.indices.contains(i) { selectedIndex = i }
    }

    func launchSelected() {
        if let s = selected, s.selectable { onActivate(s) }
    }

    func icon(for app: AppEntry) -> NSImage {
        icon(app.url)
    }

    func icon(_ url: URL) -> NSImage {
        if let cached = iconCache[url] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[url] = image
        return image
    }

    private func applyFilter(keep: Bool = false) {
        let prev = selected?.id
        var r: [LauncherItem] = []
        switch LauncherMode.parse(query) {
        case .calc(let e):
            search.search("")
            if let v = LauncherCalc.evaluate(e) {
                r.append(.calc(e, LauncherCalc.format(v)))
            } else {
                r.append(.hint(String(localized: "Calculator"), String(localized: "Type an expression, e.g. =12*4+3")))
            }
        case .actions(let q):
            search.search("")
            r = LauncherAction.matching(q).map(LauncherItem.action)
        case .clipboard(let q):
            search.search("")
            let c = clips.items.filter { q.isEmpty || $0.text.localizedStandardContains(q) }
            r = c.map(LauncherItem.clip)
            if clips.items.isEmpty {
                r.append(.hint(String(localized: "Clipboard"), String(localized: "Copied text shows up here.")))
            }
        case .apps(let q):
            if LauncherCalc.looksLikeMath(q), let v = LauncherCalc.evaluate(q) {
                r.append(.calc(q, LauncherCalc.format(v)))
            }
            r += ranker.rank(all, query: q, usage: usage, pinned: pinned).map(LauncherItem.app)
            if q.isEmpty {
                r.append(.hint(String(localized: "Tip"), String(localized: "= calculator   > actions   : clipboard")))
            } else {
                search.search(q)
                r += files.map(LauncherItem.file)
            }
        }
        results = r
        if keep, let prev, let i = r.firstIndex(where: { $0.id == prev }) {
            selectedIndex = i
        } else {
            selectedIndex = r.firstIndex(where: \.selectable) ?? 0
        }
    }
}
