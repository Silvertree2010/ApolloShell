import AppKit
import ApolloShellCore
import Observation

enum LauncherItem: Identifiable, Equatable {
    case app(AppEntry)
    case calc(String, String)
    case action(LauncherAction)
    case clip(ClipEntry)
    case file(URL)
    case hint(String, String)

    var id: String {
        switch self {
        case .app(let a): "a:" + a.url.path
        case .calc(let e, _): "c:" + e
        case .action(let a): "x:" + a.rawValue
        case .clip(let c): "p:" + c.id.uuidString
        case .file(let u): "f:" + u.path
        case .hint(let t, _): "h:" + t
        }
    }

    var selectable: Bool {
        if case .hint = self { return false }
        return true
    }
}

struct ClipEntry: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let date: Date
}

@MainActor
@Observable
final class ClipboardHistory {
    static let shared = ClipboardHistory()
    static let limit = 40

    private(set) var items: [ClipEntry] = []
    @ObservationIgnored private var count = NSPasteboard.general.changeCount
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ownChange = -1

    func start() {
        guard timer == nil else { return }
        timer = .repeating(every: 1, tolerance: 0.3, owner: self) { $0.poll() }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != count else { return }
        count = pb.changeCount
        guard count != ownChange else { return }
        let types = pb.types ?? []
        let secret = types.contains { $0.rawValue == "org.nspasteboard.ConcealedType" || $0.rawValue == "org.nspasteboard.TransientType" }
        guard !secret, let s = pb.string(forType: .string) else { return }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count < 20_000 else { return }
        items.removeAll { $0.text == s }
        items.insert(ClipEntry(text: s, date: Date()), at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
    }

    func copy(_ e: ClipEntry) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(e.text, forType: .string)
        ownChange = pb.changeCount
        count = pb.changeCount
        items.removeAll { $0.id == e.id }
        items.insert(ClipEntry(text: e.text, date: Date()), at: 0)
    }

    func clear() { items.removeAll() }
}

@MainActor
final class LauncherFileSearch: NSObject {
    private var query: NSMetadataQuery?
    private var term = ""
    var onResults: ([URL]) -> Void = { _ in }

    func search(_ t: String) {
        let q = t.trimmingCharacters(in: .whitespaces)
        guard q != term else { return }
        term = q
        stop()
        guard q.count >= 2 else { onResults([]); return }
        let m = NSMetadataQuery()
        m.searchScopes = [NSMetadataQueryUserHomeScope]
        m.predicate = NSPredicate(format: "%K CONTAINS[cd] %@ AND NOT (%K == 'com.apple.application-bundle')",
                                  NSMetadataItemFSNameKey, q, NSMetadataItemContentTypeKey)
        m.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        NotificationCenter.default.addObserver(self, selector: #selector(done), name: .NSMetadataQueryDidFinishGathering, object: m)
        query = m
        m.start()
    }

    @objc private func done(_ n: Notification) {
        guard let m = n.object as? NSMetadataQuery, m === query else { return }
        m.disableUpdates()
        var r: [URL] = []
        for i in 0..<min(m.resultCount, 60) {
            guard let it = m.result(at: i) as? NSMetadataItem, let p = it.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            if p.contains("/Library/") || p.contains("/.") { continue }
            r.append(URL(fileURLWithPath: p))
            if r.count == 8 { break }
        }
        m.stop()
        onResults(r)
    }

    func stop() {
        if let query {
            query.stop()
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
        }
        query = nil
    }
}

@MainActor
enum LauncherActions {
    static var openSettings: () -> Void = {}
    static var openSession: () -> Void = {}

    static func run(_ a: LauncherAction) {
        switch a {
        case .lock: _ = UtilitiesKeys.post(.lockScreen)
        case .sleep:
            let c = SessionAction.sleep.command
            _ = Subprocess.launch(c.executable, c.arguments)
        case .darkMode: UtilitiesAppearance.setDark(!UtilitiesAppearance.isDark())
        case .screenshot:
            if let k = UtilitiesKeys.symbolic(id: UtilitiesHotKey.screenshotToolbarID, fallback: .screenshotToolbarDefault), UtilitiesKeys.post(k) { return }
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"), configuration: .init())
        case .showDesktop:
            if let k = UtilitiesKeys.symbolic(id: UtilitiesHotKey.showDesktopID, fallback: .showDesktopDefault) { _ = UtilitiesKeys.post(k) }
        case .emptyTrash: DockTrash.empty {}
        case .settings: openSettings()
        case .restart, .shutDown, .logOut: openSession()
        }
    }
}
