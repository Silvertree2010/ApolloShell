import Foundation

public struct SettingDef: Sendable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case toggle
        case choice([Opt])
        case link
    }

    public struct Opt: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
    }

    public let id: String
    public let page: String
    public let group: String
    public let title: String
    public let help: String
    public let keys: [String]
    public let kind: Kind
    public let parent: String?
    let rd: @Sendable (ShellSettings) -> String
    let wr: @Sendable (inout ShellSettings, String) -> Void

    public func value(in s: ShellSettings) -> String { rd(s) }

    public func isOn(in s: ShellSettings) -> Bool { rd(s) == "1" }

    public func write(_ v: String, to s: inout ShellSettings) {
        guard kind != .link else { return }
        if case .choice(let o) = kind, !o.contains(where: { $0.id == v }) { return }
        wr(&s, v)
    }

    public func toggle(in s: inout ShellSettings) {
        guard kind == .toggle else { return }
        wr(&s, isOn(in: s) ? "0" : "1")
    }

    public var standard: String { rd(.firstLaunch) }

    public func modified(in s: ShellSettings) -> Bool {
        kind != .link && rd(s) != standard
    }

    public func reset(in s: inout ShellSettings) {
        guard kind != .link else { return }
        wr(&s, standard)
    }

    public func enabled(in s: ShellSettings) -> Bool {
        guard let p = parent, let d = SettingsIndex.find(p) else { return true }
        return d.isOn(in: s) && d.enabled(in: s)
    }

    public func action(in s: ShellSettings) -> String {
        switch kind {
        case .toggle: (isOn(in: s) ? "Turn Off " : "Turn On ") + title
        case .choice: title + ": " + label(in: s)
        case .link: title
        }
    }

    public func label(in s: ShellSettings) -> String {
        switch kind {
        case .toggle: isOn(in: s) ? "On" : "Off"
        case .choice(let o): o.first { $0.id == rd(s) }?.title ?? rd(s)
        case .link: ""
        }
    }
}

public struct SettingsQuery: Sendable, Equatable {
    public var words: [String]
    public var modified: Bool

    public init(_ raw: String) {
        var m = false
        var w: [String] = []
        for t in raw.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            let l = SettingsIndex.fold(String(t))
            if l.hasPrefix("@") {
                if "@modified".hasPrefix(l), l.count >= 2 { m = true }
                continue
            }
            if !l.isEmpty { w.append(l) }
        }
        words = w
        modified = m
    }

    public var isEmpty: Bool { words.isEmpty && !modified }
}

public struct SettingsPage: Sendable, Equatable {
    public let id: String
    public let title: String
    public let keys: [String]

    public init(id: String, title: String, keys: [String] = []) {
        self.id = id
        self.title = title
        self.keys = keys
    }
}

public enum SettingsHit: Sendable, Identifiable {
    case page(SettingsPage, Int)
    case setting(SettingDef, Int)

    public var id: String {
        switch self {
        case .page(let p, _): "page:" + p.id
        case .setting(let d, _): d.id
        }
    }

    public var score: Int {
        switch self {
        case .page(_, let s), .setting(_, let s): s
        }
    }

    public var page: String {
        switch self {
        case .page(let p, _): p.id
        case .setting(let d, _): d.page
        }
    }
}

public enum SettingsIndex {
    public static func find(_ id: String) -> SettingDef? { byID[id] }

    static let byID: [String: SettingDef] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    public static func on(page: String, group: String? = nil) -> [SettingDef] {
        all.filter { $0.page == page && (group == nil || $0.group == group) }
    }

    public static func modified(in s: ShellSettings) -> [SettingDef] {
        all.filter { $0.modified(in: s) }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func tier(_ w: String, title: String, group: String, keys: [String], help: String) -> Int {
        let t = fold(title)
        if t == w { return 100 }
        if t.hasPrefix(w) { return 90 }
        let tw = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if tw.contains(where: { $0.hasPrefix(w) }) { return 80 }
        let deep = w.count >= 3
        if deep, t.contains(w) { return 60 }
        let g = fold(group)
        if g.hasPrefix(w) { return 50 }
        if deep, g.contains(w) { return 45 }
        let k = keys.map(fold)
        if k.contains(where: { $0.hasPrefix(w) }) { return 40 }
        if deep, k.contains(where: { $0.contains(w) }) { return 35 }
        if w.count >= 4, fold(help).contains(w) { return 20 }
        return 0
    }

    static func score(_ q: SettingsQuery, title: String, group: String, keys: [String], help: String) -> Int? {
        guard !q.words.isEmpty else { return 1 }
        var lo = Int.max
        for w in q.words {
            let t = tier(w, title: title, group: group, keys: keys, help: help)
            if t == 0 { return nil }
            lo = min(lo, t)
        }
        return lo
    }

    public static func search(_ raw: String, in s: ShellSettings, pages: [SettingsPage]) -> [SettingsHit] {
        let q = SettingsQuery(raw)
        guard !q.isEmpty else { return [] }
        var out: [(SettingsHit, Int)] = []
        var n = 0
        if !q.modified {
            for p in pages {
                if let sc = score(q, title: p.title, group: "", keys: p.keys, help: "") {
                    out.append((.page(p, sc + 5), n))
                }
                n += 1
            }
        }
        let names = Dictionary(pages.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        for d in all {
            n += 1
            if q.modified && !d.modified(in: s) { continue }
            guard let sc = score(q, title: d.title, group: d.group + " " + (names[d.page] ?? ""), keys: d.keys, help: d.help)
            else { continue }
            out.append((.setting(d, sc), n))
        }
        return out.sorted { a, b in a.0.score == b.0.score ? a.1 < b.1 : a.0.score > b.0.score }.map(\.0)
    }

    public static func actions(_ raw: String, in s: ShellSettings, limit: Int = 8) -> [SettingDef] {
        var out: [SettingDef] = []
        for h in search(raw, in: s, pages: []) {
            guard case .setting(let d, let sc) = h, sc >= 35, d.enabled(in: s) else { continue }
            out.append(d)
            if out.count == limit { break }
        }
        return out
    }

    public static func counts(_ hits: [SettingsHit]) -> [String: Int] {
        var c: [String: Int] = [:]
        for h in hits { c[h.page, default: 0] += 1 }
        return c
    }

    static func tg(_ id: String, _ page: String, _ group: String, _ title: String, _ help: String = "",
                   _ keys: [String] = [], parent: String? = nil,
                   _ get: @escaping @Sendable (ShellSettings) -> Bool,
                   _ set: @escaping @Sendable (inout ShellSettings, Bool) -> Void) -> SettingDef {
        SettingDef(id: id, page: page, group: group, title: title, help: help, keys: keys, kind: .toggle, parent: parent,
                   rd: { get($0) ? "1" : "0" }, wr: { set(&$0, $1 == "1") })
    }

    static func ch(_ id: String, _ page: String, _ group: String, _ title: String, _ help: String = "",
                   _ keys: [String] = [], parent: String? = nil, _ opts: [(String, String)],
                   _ get: @escaping @Sendable (ShellSettings) -> String,
                   _ set: @escaping @Sendable (inout ShellSettings, String) -> Void) -> SettingDef {
        SettingDef(id: id, page: page, group: group, title: title, help: help, keys: keys,
                   kind: .choice(opts.map { SettingDef.Opt(id: $0.0, title: $0.1) }), parent: parent, rd: get, wr: set)
    }

    static func ln(_ id: String, _ page: String, _ group: String, _ title: String, _ help: String = "",
                   _ keys: [String] = []) -> SettingDef {
        SettingDef(id: id, page: page, group: group, title: title, help: help, keys: keys, kind: .link, parent: nil,
                   rd: { _ in "" }, wr: { _, _ in })
    }

    public static let all: [SettingDef] = [
        ln("start.login", "general", "Start", "Start at Login", "Open ApolloShell when you log in.", ["autostart", "login item", "boot"]),
        tg("dock.hide", "general", "Dock", "Hide Apple's Dock",
           "While ApolloShell runs. If ApolloShell is force-quit, Apple's Dock stays hidden until ApolloShell starts and quits normally again.",
           ["apple dock", "autohide"], { $0.appleDockHiding.hideWhileRunning }, { $0.appleDockHiding.hideWhileRunning = $1 }),
        ln("perm.ax", "general", "Permissions", "Accessibility", "Needed to move windows and read the front app.", ["permission", "privacy", "access"]),
        ln("perm.events", "general", "Permissions", "System Events", "Needed for a few system actions.", ["permission", "automation", "apple events"]),
        ln("files.manager", "general", "File Manager", "File Manager", "The app behind the folder button at the top of the dock.", ["finder", "forklift", "files"]),

        ln("keys.global", "hotKeys", "Global", "Global Shortcuts", "Launcher, Dashboard, Quick Actions and Nexus.", ["hotkey", "keyboard", "shortcut", "launcher", "dashboard", "nexus"]),
        ln("keys.presets", "hotKeys", "Presets", "Shortcut Presets", "Default or Hyper Key.", ["hyper", "karabiner", "f20"]),

        ln("bar.blocks", "bar", "Building Blocks", "Building Blocks", "Arrange, add and configure what the bar shows.",
           ["dock", "spaces", "clock", "status", "wifi", "bluetooth", "battery", "sound", "weather", "media", "gap", "app button", "power", "icon size", "smart groups", "window previews", "12-hour"]),
        ln("bar.screens", "bar", "Screens", "Screens", "Which displays get a bar.", ["display", "monitor", "external"]),
        ch("bar.side", "bar", "Placement", "Position", "The screen edge the bar sits on.", ["left", "right", "edge", "side"],
           [("left", "Left"), ("right", "Right")], { $0.bar.side.rawValue }, { $0.bar.side = BarSide(rawValue: $1) ?? .left }),
        tg("bar.clear", "bar", "Placement", "Keep Windows Clear",
           "Moves windows out from under the bar. Turn it off if a window manager arranges your windows.",
           ["tiling", "window manager", "overlap"], { $0.bar.keepWindowsClear }, { $0.bar.keepWindowsClear = $1 }),

        ln("qa.cards", "utilities", "Cards", "Quick Actions Cards", "Cards and quick toggles in the panel at the bottom corner.",
           ["utilities", "keep awake", "focus", "shortcut", "toggle", "sound", "control center"]),

        ln("launcher.pinned", "launcher", "Pinned Apps", "Pinned Apps", "The apps shown before you type.", ["favorites", "pin", "order"]),

        ln("dash.edit", "dashboard", "Pages", "Edit Dashboard", "Pages and widgets are edited right in the Dashboard.", ["widgets", "bento", "pages", "layout"]),
        ln("dash.weather", "dashboard", "Weather Source", "Weather Source", "Where the forecast comes from.", ["open-meteo", "met norway", "yr", "wttr", "forecast"]),

        tg("lyrics.on", "lyrics", "Lyrics", "Lyrics",
           "Synced lyrics in the Media tab and the Lyrics widget. Each new song asks lrclib.net once, then it is cached.",
           ["songtext", "karaoke", "lrclib", "music", "spotify"], { $0.lyrics.enabled }, { $0.lyrics.enabled = $1 }),
        tg("lyrics.desktop", "lyrics", "Desktop", "Desktop Lyrics", "The current line on the desktop. Clicks go through.",
           ["wallpaper", "floating", "overlay"], parent: "lyrics.on", { $0.lyrics.desktop }, { $0.lyrics.desktop = $1 }),
        ch("lyrics.edge", "lyrics", "Desktop", "Position", "Where on the screen the lines sit.", ["bottom", "center", "top"],
           parent: "lyrics.desktop", [("bottom", "Bottom"), ("center", "Center"), ("top", "Top")],
           { $0.lyrics.desktopEdge.rawValue }, { $0.lyrics.desktopEdge = ShellSettings.LyricsEdge(rawValue: $1) ?? .bottom }),
        tg("lyrics.above", "lyrics", "Desktop", "Above Windows", "Keeps the lines over every window instead of on the wallpaper.",
           ["always on top", "front"], parent: "lyrics.desktop", { $0.lyrics.desktopAbove }, { $0.lyrics.desktopAbove = $1 }),
        tg("lyrics.mood", "lyrics", "Feel", "Style by Mood",
           "Font and motion follow the song's genre and energy. Classified on this Mac when Apple Intelligence is on, otherwise by the iTunes catalogue.",
           ["genre", "font", "animation", "rap", "metal"], parent: "lyrics.on", { $0.lyrics.moodStyles }, { $0.lyrics.moodStyles = $1 }),
        tg("lyrics.pulse", "lyrics", "Feel", "Live Pulse",
           "Lines react to loudness and beats. Needs Screen Recording access to hear system audio; nothing is recorded.",
           ["beat", "audio", "visualizer", "screen recording"], parent: "lyrics.on", { $0.lyrics.livePulse }, { $0.lyrics.livePulse = $1 }),
        tg("lyrics.sync", "lyrics", "Timing", "Auto Sync",
           "Listens for sung words and corrects the timing by up to ±0.35 s. Needs Screen Recording access.",
           ["offset", "delay", "late", "early", "timing"], parent: "lyrics.on", { $0.lyrics.autoSync }, { $0.lyrics.autoSync = $1 }),

        tg("desk.clock", "desktop", "Clock", "Desktop Clock", "A large clock on the wallpaper, opposite the bar.",
           ["time", "date", "wallpaper"], { $0.background.desktopClock }, { $0.background.desktopClock = $1 }),
        tg("osd.on", "desktop", "OSD", "Show OSD", "Volume, brightness, keyboard layout and Caps Lock. Turn off to use another OSD app.",
           ["volume", "brightness", "caps lock", "hud"], { $0.features.osd }, { $0.features.osd = $1 }),
        tg("osd.replace", "desktop", "OSD", "Replace macOS OSD",
           "Handles the volume and brightness keys itself so only one OSD shows. Needs Accessibility.",
           ["media keys", "system hud"], parent: "osd.on", { $0.features.replaceSystemOSD }, { $0.features.replaceSystemOSD = $1 }),
        tg("hover.dash", "desktop", "Open on Hover", "Dashboard on Hover", "Opens when the pointer hits the top middle edge.",
           ["edge", "pointer", "mouse"], { $0.features.dashboardHover }, { $0.features.dashboardHover = $1 }),
        tg("hover.qa", "desktop", "Open on Hover", "Quick Actions on Hover",
           "Opens when the pointer hits the bottom corner. Turn off if you use a hot corner there.",
           ["hot corner", "utilities", "pointer"], { $0.features.utilitiesHover }, { $0.features.utilitiesHover = $1 }),
        tg("toast.charger", "desktop", "Toasts", "Charger", "When the charger is plugged in or pulled.",
           ["notification", "power", "charging"], { $0.toasts.chargingChanged }, { $0.toasts.chargingChanged = $1 }),
        tg("toast.battery", "desktop", "Toasts", "Battery Warnings", "On battery, at 20, 10 and 5 %.",
           ["notification", "low battery"], { $0.toasts.batteryWarnings }, { $0.toasts.batteryWarnings = $1 }),
        tg("toast.out", "desktop", "Toasts", "Audio Output", "When the output device changes.",
           ["notification", "headphones", "speakers", "airpods"], { $0.toasts.audioOutputChanged }, { $0.toasts.audioOutputChanged = $1 }),
        tg("toast.in", "desktop", "Toasts", "Audio Input", "When the microphone changes.",
           ["notification", "microphone"], { $0.toasts.audioInputChanged }, { $0.toasts.audioInputChanged = $1 }),

        ln("theme.list", "themes", "Theme", "Theme", "The look of the whole shell, from one CSS file.", ["css", "color", "font", "dark", "light", "appearance"]),
        ln("theme.market", "themes", "Marketplace", "Marketplace", "Themes made by others.", ["download", "community"]),
        ch("nexus.look", "themes", "Nexus", "Nexus Look", "How this window is drawn.", ["settings window", "style", "glass"],
           [("graphite", "Graphite"), ("glass", "Glass"), ("plain", "Plain")],
           { $0.nexus.look.rawValue }, { $0.nexus.look = ShellSettings.NexusLook(rawValue: $1) ?? .graphite }),

        ln("upd.status", "about", "Updates", "Check for Updates", "Version, last check and what is new.", ["version", "release", "sparkle", "homebrew", "upgrade"]),
        tg("upd.check", "about", "Updates", "Check Automatically", "Looks for a new release once a day.",
           ["update"], { $0.updates.checkAutomatically }, { $0.updates.checkAutomatically = $1 }),
        tg("upd.install", "about", "Updates", "Install Automatically",
           "Installs in the background. The new version starts the next time ApolloShell does.",
           ["update", "upgrade"], { $0.updates.installAutomatically }, { $0.updates.installAutomatically = $1 }),
        ch("crash.mode", "about", "Crash Reports", "Send Crash Reports",
           "Sends the ApolloShell and macOS versions, the Mac model and where in the code it crashed. No files, names or device IDs.",
           ["privacy", "telemetry", "diagnostics"], [("ask", "Ask Each Time"), ("always", "Always"), ("never", "Never")],
           { $0.crashReports.mode.rawValue }, { $0.crashReports.mode = CrashReportSettings.Mode(rawValue: $1) ?? .ask }),
        ln("about.system", "about", "System", "System", "This Mac and this copy of ApolloShell.", ["macos", "chip", "uptime", "kernel"]),
        ln("about.intro", "about", "Introduction", "Show Introduction", "The first-run tour again.", ["onboarding", "welcome", "tour"]),
        ln("adv.only", "about", "Advanced", "Launcher Only", "Only the launcher runs: no bar, Dashboard, Quick Actions or toasts.", ["minimal", "spotlight"]),
        ln("adv.backup", "about", "Backup", "Export and Import Settings", "Every setting as one JSON file.", ["backup", "json", "restore", "transfer"]),
        ln("adv.reset", "about", "Reset", "Reset All Settings", "Back to how a fresh install looks.", ["defaults", "factory"]),
        ln("adv.remove", "about", "Reset", "Uninstall ApolloShell", "Removes settings, data and permissions.", ["remove", "delete"]),
    ]
}
