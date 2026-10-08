import Foundation

public struct DockGroup: Equatable, Sendable, Identifiable {
    public var key: String
    public var title: String
    public var symbol: String
    public var members: [DockSlot]
    public var id: String { "g:" + key }

    public init(key: String, title: String, symbol: String, members: [DockSlot]) {
        self.key = key
        self.title = title
        self.symbol = symbol
        self.members = members
    }
}

public enum DockItem: Equatable, Sendable, Identifiable {
    case app(DockSlot)
    case group(DockGroup)

    public var id: String {
        switch self {
        case .app(let s): s.bundleID
        case .group(let g): g.id
        }
    }
}

public enum DockCategory {
    public struct Kind: Equatable, Sendable {
        public var key: String
        public var title: String
        public var symbol: String
    }

    public static let other = Kind(key: "other", title: "Other", symbol: "square.grid.2x2")

    static let kinds: [String: Kind] = {
        let t: [(String, String, String, [String])] = [
            ("write", "Notes & Writing", "note.text", ["productivity"]),
            ("dev", "Developer", "hammer", ["developer-tools"]),
            ("design", "Design", "paintbrush.pointed", ["graphics-design", "photography"]),
            ("media", "Media", "play.rectangle", ["music", "video", "entertainment"]),
            ("chat", "Social", "bubble.left.and.bubble.right", ["social-networking"]),
            ("web", "Web", "globe", ["navigation"]),
            ("work", "Work", "briefcase", ["business", "finance"]),
            ("tools", "Utilities", "wrench.and.screwdriver", ["utilities"]),
            ("games", "Games", "gamecontroller", ["games", "action-games", "adventure-games", "arcade-games", "board-games", "card-games", "casino-games", "dice-games", "educational-games", "family-games", "kids-games", "music-games", "puzzle-games", "racing-games", "role-playing-games", "simulation-games", "sports-games", "strategy-games", "trivia-games", "word-games"]),
            ("read", "Reading & Learning", "book", ["books", "education", "reference", "news", "magazines"]),
            ("life", "Lifestyle", "heart", ["lifestyle", "healthcare-fitness", "medical", "sports", "travel", "food-and-drink", "weather"]),
        ]
        var m: [String: Kind] = [:]
        for (k, title, sym, cats) in t {
            for c in cats { m["public.app-category." + c] = Kind(key: k, title: title, symbol: sym) }
        }
        return m
    }()

    static let known: [String: String] = [
        "com.apple.Safari": "web", "com.google.Chrome": "web", "org.mozilla.firefox": "web", "com.vivaldi.Vivaldi": "web",
        "company.thebrowser.Browser": "web", "com.brave.Browser": "web", "com.microsoft.edgemac": "web", "app.zen-browser.zen": "web",
        "com.apple.Notes": "write", "md.obsidian": "write", "com.apple.TextEdit": "write", "notion.id": "write",
        "com.apple.iWork.Pages": "write", "com.microsoft.Word": "write", "com.apple.reminders": "write",
        "com.apple.Terminal": "dev", "net.kovidgoyal.kitty": "dev", "com.googlecode.iterm2": "dev", "com.mitchellh.ghostty": "dev",
        "com.microsoft.VSCode": "dev", "com.apple.dt.Xcode": "dev", "dev.zed.Zed": "dev", "com.todesktop.230313mzl4w4u92": "dev",
        "com.spotify.client": "media", "com.apple.Music": "media", "com.apple.TV": "media", "com.apple.podcasts": "media",
        "com.apple.MobileSMS": "chat", "com.hnc.Discord": "chat", "ru.keepcoder.Telegram": "chat", "net.whatsapp.WhatsApp": "chat",
        "com.tinyspeck.slackmacgap": "chat", "com.apple.mail": "chat", "com.microsoft.teams2": "chat",
        "com.adobe.illustrator": "design", "com.adobe.InDesign": "design", "com.adobe.Photoshop": "design", "com.figma.Desktop": "design",
        "com.apple.Photos": "design", "com.apple.Preview": "design",
        "com.apple.systempreferences": "tools", "com.apple.ActivityMonitor": "tools", "com.apple.calculator": "tools",
    ]

    public static func kind(bundleID: String, category: String?) -> Kind {
        if let k = known[bundleID], let kind = kinds.values.first(where: { $0.key == k }) { return kind }
        if let category, let kind = kinds[category] { return kind }
        return other
    }

    public static func kind(key: String) -> Kind {
        kinds.values.first { $0.key == key } ?? other
    }
}

public enum DockClustering {
    public static let limit = 9
    public static let keep = 4
    public static let minUse: Double = 3

    public static func items(
        _ slots: [DockSlot],
        fixed: Set<String> = [],
        weight: (String) -> Double,
        kind: (String) -> DockCategory.Kind,
        partner: (String) -> String? = { _ in nil },
        limit: Int = DockClustering.limit,
        keep: Int = DockClustering.keep
    ) -> [DockItem] {
        guard slots.count > limit else { return slots.map(DockItem.app) }
        let ranked = slots.enumerated()
            .filter { !fixed.contains($0.element.bundleID) }
            .sorted { a, b in
                let wa = weight(a.element.bundleID), wb = weight(b.element.bundleID)
                return wa != wb ? wa > wb : a.offset < b.offset
            }
        var single = fixed
        for (_, s) in ranked.prefix(max(0, min(keep, limit - fixed.count - 1))) where weight(s.bundleID) >= minUse {
            single.insert(s.bundleID)
        }
        let rest = slots.filter { !single.contains($0.bundleID) }
        var key: [String: String] = [:]
        for s in rest { key[s.bundleID] = kind(s.bundleID).key }
        for s in rest where key[s.bundleID] == DockCategory.other.key {
            if let p = partner(s.bundleID), case let pk = key[p] ?? kind(p).key, pk != DockCategory.other.key {
                key[s.bundleID] = pk
            }
        }
        var order: [String] = []
        var groups: [String: [DockSlot]] = [:]
        for s in rest {
            let k = key[s.bundleID]!
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(s)
        }
        let room = max(1, limit - single.count)
        while order.count > room {
            let small = order.filter { $0 != DockCategory.other.key }
                .min { (groups[$0]!.count, order.firstIndex(of: $0)!) < (groups[$1]!.count, order.firstIndex(of: $1)!) }
            guard let small else { break }
            let moved = groups.removeValue(forKey: small)!
            order.removeAll { $0 == small }
            if groups[DockCategory.other.key] == nil { order.append(DockCategory.other.key) }
            groups[DockCategory.other.key, default: []].append(contentsOf: moved)
        }
        var loose = Set<String>()
        for k in order where groups[k]!.count == 1 { loose.insert(groups[k]![0].bundleID) }
        var result: [DockItem] = []
        var placed = Set<String>()
        for s in slots {
            if single.contains(s.bundleID) || loose.contains(s.bundleID) {
                result.append(.app(s))
                continue
            }
            let k = key[s.bundleID]!
            let gk = groups[k] != nil ? k : DockCategory.other.key
            guard !placed.contains(gk), let members = groups[gk] else { continue }
            placed.insert(gk)
            let kd = DockCategory.kind(key: gk)
            result.append(.group(DockGroup(key: gk, title: kd.title, symbol: kd.symbol, members: members)))
        }
        return result
    }
}

public struct DockUsage: Codable, Sendable, Equatable {
    public static let window: TimeInterval = 120
    public var uses: UsageStats
    var pairs: [String: Double]
    var last: String?
    var lastAt: Date?

    public init() {
        uses = UsageStats()
        pairs = [:]
    }

    static func pk(_ a: String, _ b: String) -> String { a < b ? a + "|" + b : b + "|" + a }

    public mutating func record(_ id: String, at date: Date = Date()) {
        uses.record(id, at: date)
        if let last, last != id, let lastAt, date.timeIntervalSince(lastAt) <= Self.window {
            pairs[Self.pk(last, id), default: 0] += 1
        }
        last = id
        lastAt = date
    }

    public func weight(_ id: String, at date: Date = Date()) -> Double { uses.weight(for: id, at: date) }

    public func partner(_ id: String, among ids: Set<String>, minimum: Double = 3) -> String? {
        var best: (String, Double)?
        for o in ids where o != id {
            let v = pairs[Self.pk(id, o)] ?? 0
            if v >= minimum, v > (best?.1 ?? 0) { best = (o, v) }
        }
        return best?.0
    }
}
