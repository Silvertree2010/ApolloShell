import Foundation
import Testing
import ApolloBase
import ApolloConfig
import ApolloStyle
import ApolloShellCore

@Suite("Default-Config 9b")
struct DefaultConfigTests {
    static let defaultFolder = PackageResources.configs.appendingPathComponent("apolloshell-default")
    static let launcherOnlyFolder = PackageResources.configs.appendingPathComponent("launcher-only")
    static let inventory = PackageResources.root
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("private/specs/0.2-framework/anhang-inventar-0.1.4.2.md")

    @Test("apolloshell-default lädt ohne jede Diagnose")
    func defaultLoadsClean() {
        let result = PackageResources.load(Self.defaultFolder, id: "apolloshell-default")
        #expect(result.ir != nil)
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
    }

    @Test("launcher-only lädt ohne jede Diagnose und enthält nur den Launcher")
    func launcherOnlyLoadsClean() throws {
        let result = PackageResources.load(Self.launcherOnlyFolder, id: "launcher-only")
        let ir = try #require(result.ir)
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(ir.surfaces.map(\.id) == ["launcher"])
        #expect(ir.styleSheets.contains { $0.url.lastPathComponent == "style.css" })
    }

    @Test("Oberflächen der Default-Config")
    func surfaces() throws {
        let ir = try #require(PackageResources.load(Self.defaultFolder, id: "apolloshell-default").ir)
        let kinds = Dictionary(uniqueKeysWithValues: ir.surfaces.map { ($0.id, $0.kind) })
        let expected = [
            "bar": "panel", "clock": "panel", "dash": "popup", "launcher": "popup", "sess": "popup", "cc": "popup",
            "osd": "osd", "default": "toast", "pill": "toast", "prefs": "window", "ob": "window",
        ]
        #expect(kinds == expected)
    }

    @Test("gespeicherte var der Default-Config")
    func persistedVars() throws {
        let ir = try #require(PackageResources.load(Self.defaultFolder, id: "apolloshell-default").ir)
        let persisted = Set(ir.vars.filter(\.persist).map(\.name))
        let expected: Set<String> = ["dt", "onboarding-done", "desktop-clock", "ws", "h24", "wp", "tmin", "bm", "hotkey-launcher", "hotkey-dashboard", "hotkey-utilities", "hotkey-session", "hotkey-settings", "file-manager"]
        #expect(persisted == expected)
    }

    struct Assignment {
        var prefix: String
        var range: ClosedRange<Int>
        var artifacts: [String]
    }

    static let assignments: [Assignment] = [
        Assignment(prefix: "SB", range: 1...15, artifacts: ["define:m-logo", "define:m-ws", "define:m-win", "define:m-tray", "define:m-clk", "define:m-st", "define:m-pw", "define:m-sp", "define:bmod"]),
        Assignment(prefix: "SB", range: 16...22, artifacts: ["surface:bar", "var:bm", "var:po", "var:pv"]),
        Assignment(prefix: "SP", range: 1...19, artifacts: ["define:p-net", "define:p-bt", "define:p-bat", "define:p-vol", "define:p-win"]),
        Assignment(prefix: "DC", range: 1...5, artifacts: ["surface:clock", "var:desktop-clock"]),
        Assignment(prefix: "SW", range: 1...4, artifacts: ["define:m-ws"]),
        Assignment(prefix: "ED", range: 1...17, artifacts: ["surface:dash", "surface:cc", "surface:launcher", "surface:sess", "surface:osd"]),
        Assignment(prefix: "SS", range: 1...3, artifacts: ["surface:bar"]),
        Assignment(prefix: "DK", range: 1...39, artifacts: ["define:m-win", "surface:bar"]),
        Assignment(prefix: "AD", range: 1...10, artifacts: ["define:pg-desk"]),
        Assignment(prefix: "LA", range: 1...25, artifacts: ["surface:launcher", "var:hotkey-launcher", "var:lres"]),
        Assignment(prefix: "LA", range: 26...27, artifacts: ["config:launcher-only"]),
        Assignment(prefix: "MP", range: 1...24, artifacts: ["shell"]),
        Assignment(prefix: "DB", range: 1...41, artifacts: ["surface:dash", "define:pane-dash", "define:pane-media", "define:pane-perf", "define:pane-wx", "define:w-wx", "define:w-user", "define:w-dt", "define:w-cal", "define:w-res", "define:w-media", "define:w-timer", "define:w-toggles", "var:dt"]),
        Assignment(prefix: "UT", range: 1...34, artifacts: ["surface:cc", "define:tile", "define:qt", "define:cslider", "var:cop"]),
        Assignment(prefix: "KA", range: 1...12, artifacts: ["define:p-bat", "define:tile"]),
        Assignment(prefix: "OB", range: 1...9, artifacts: ["surface:ob", "var:onboarding-done", "define:pg-about"]),
        Assignment(prefix: "NX", range: 1...32, artifacts: ["surface:prefs", "define:pg-look", "define:pg-bar", "define:pg-wx", "define:pg-keys", "define:pg-desk", "define:pg-about"]),
        Assignment(prefix: "SM", range: 1...21, artifacts: ["surface:sess", "define:sb"]),
        Assignment(prefix: "OSD", range: 1...8, artifacts: ["surface:osd"]),
        Assignment(prefix: "TO", range: 1...17, artifacts: ["surface:default", "surface:pill"]),
        Assignment(prefix: "HK", range: 1...16, artifacts: ["var:hotkey-launcher", "var:hotkey-dashboard", "var:hotkey-utilities", "var:hotkey-session", "var:hotkey-settings", "define:pg-keys"]),
        Assignment(prefix: "WG", range: 1...16, artifacts: ["surface:bar"]),
        Assignment(prefix: "FS", range: 1...7, artifacts: ["surface:bar"]),
        Assignment(prefix: "MS", range: 1...9, artifacts: ["surface:bar"]),
        Assignment(prefix: "UP", range: 1...11, artifacts: ["shell"]),
        Assignment(prefix: "CR", range: 1...14, artifacts: ["shell"]),
        Assignment(prefix: "SI", range: 1...6, artifacts: ["shell"]),
    ]

    static let presetLets = [
        "SB-Presets": ["sidebar-caelestia", "sidebar-minimal", "sidebar-dock-only", "sidebar-everything"],
        "DB-Presets": ["dashboard-caelestia", "dashboard-compact", "dashboard-calendar-weather"],
        "UT-Presets": ["utilities-standard", "utilities-minimal", "utilities-audio", "utilities-everything"],
    ]

    @Test("jede Zuordnung zeigt auf etwas, das die Config hat")
    func assignmentsExist() throws {
        let ir = try #require(PackageResources.load(Self.defaultFolder, id: "apolloshell-default", allDefines: true).ir)
        let surfaces = Set(ir.surfaces.map(\.id))
        let vars = Set(ir.vars.map(\.name))
        for assignment in Self.assignments {
            for artifact in assignment.artifacts {
                let parts = artifact.split(separator: ":", maxSplits: 1).map(String.init)
                switch parts[0] {
                case "surface": #expect(surfaces.contains(parts[1]), "\(assignment.prefix): \(artifact)")
                case "define": #expect(ir.defines[parts[1]] != nil, "\(assignment.prefix): \(artifact)")
                case "var": #expect(vars.contains(parts[1]), "\(assignment.prefix): \(artifact)")
                case "config":
                    let shell = PackageResources.configs.appendingPathComponent(parts[1]).appendingPathComponent("shell.kdl")
                    #expect(FileManager.default.fileExists(atPath: shell.path), "\(artifact)")
                case "shell": break
                default: Issue.record("unbekannte Art \(artifact)")
                }
            }
        }
    }

    @Test("jede Inventar-ID aus default-config.md 11 ist zugeordnet", .enabled(if: FileManager.default.fileExists(atPath: DefaultConfigTests.inventory.path)))
    func inventoryCovered() throws {
        let text = try String(contentsOf: Self.inventory, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"^\| ?([A-Z]{2,3})-([0-9]{2})\b"#, options: .anchorsMatchLines)
        let range = NSRange(text.startIndex..., in: text)
        var ids: [(String, Int)] = []
        for match in regex.matches(in: text, range: range) {
            let prefix = String(text[Range(match.range(at: 1), in: text)!])
            let number = Int(text[Range(match.range(at: 2), in: text)!])!
            ids.append((prefix, number))
        }
        #expect(ids.count > 400)
        for (prefix, number) in ids {
            let covered = Self.assignments.contains { $0.prefix == prefix && $0.range.contains(number) }
            #expect(covered, "\(prefix)-\(String(format: "%02d", number)) ohne Zuordnung")
        }
        for heading in Self.presetLets.keys {
            #expect(text.contains("### \(heading)"), "\(heading)")
        }
    }

    static let derived: [String: [String]] = [
        "--apollo-bar-fill": ["--apollo-bar-color", "--apollo-bar-gradient", "--apollo-bar-opacity"],
        "--apollo-panel-fill": ["--apollo-panel-color", "--apollo-panel-gradient", "--apollo-panel-opacity"],
        "--apollo-card-fill": ["--apollo-card-color", "--apollo-card-gradient"],
        "--apollo-accent-fill": ["--apollo-accent-color", "--apollo-accent-gradient"],
        "--apollo-toast-fill": ["--apollo-toast-color", "--apollo-toast-gradient"],
        "--apollo-launcher-highlight-fill": ["--apollo-launcher-highlight-color", "--apollo-launcher-highlight-gradient"],
        "--apollo-surface-fill": ["--apollo-surface-color", "--apollo-surface-gradient", "--apollo-surface-opacity"],
        "--apollo-background-fill": ["--apollo-background-color", "--apollo-background-gradient"],
    ]

    static let cards = [".card", ".card-weather", ".card-user", ".card-clock", ".card-calendar", ".card-resources", ".card-media", ".media-source", ".popout-card", ".utilities-card", ".onboarding-card", ".weather-hero", ".weather-hours", ".weather-day"]
    static let panels = ["#dashboard", "#utilities", "#launcher", "#session"]

    static let placesFrom02: [String: [String]] = [
        "--apollo-danger-color": [".quick-toggle"],
        "--apollo-card-radius": [".now-playing-cover", ".now-playing-art"],
        "--apollo-accent-color": [".timer-ring", ".timer-toggle", ".now-playing", ".brightness-slider"],
        "--apollo-on-accent-color": [".timer-toggle", ".brightness-slider"],
    ]

    static let allowedPlaces: [String: [String]] = allowedPlaces0142.merging(placesFrom02) { $0 + $1 }

    static let allowedPlaces0142: [String: [String]] = [
        "--apollo-separator-color": [".launcher-separator"],
        "--apollo-border-color": cards,
        "--apollo-border-width": cards,
        "--apollo-shadow-opacity": [".audio-mute", ".osd-slider", ".audio-slider"],
        "--apollo-text-color": [".launcher-"],
        "--apollo-secondary-text-color": [".launcher-"],
        "--apollo-on-accent-color": [".space-number", ".space-dot", ".popout-status-circle", ".popout-capsule", ".dashboard-tab", ".card-user-avatar", ".card-calendar-day", ".media-play", ".perf-badge-text", ".perf-tank-bolt", ".perf-tank-percent", ".perf-tank-status", ".weather-place", ".weather-day-name", ".audio-mute", ".quick-toggle", ".osd-slider", ".toast-chip", ".audio-slider", ".keep-awake-chip"],
        "--apollo-accent-color": [":root", ".space-pill", ".sidebar-timer-ring", ".space-mark", ".popout-status-circle", ".popout-capsule", ".popout-battery-bolt", ".dashboard-tab-pill", ".card-user-avatar", ".card-calendar-day", ".media-play", ".perf-graph", ".perf-badge-shape", ".perf-ring", ".perf-hero-title", ".perf-gauge", ".perf-storage-glyph", ".perf-memory-glyph", ".perf-network-glyph", ".perf-net-down", ".perf-rate-glyph", ".perf-tank", ".perf-tank-head", ".weather-place", ".weather-day-name", ".audio-mute", ".audio-slider", ".quick-toggle", ".session-mark", ".osd-slider", ".toast-chip", ".onboarding-dot", ".keep-awake-chip", ".dashboard-tab", ".card-resource-ring", ".card-media-arc", ".media-empty-badge", ".media-timeline", ".card-media-bar"],
        "--apollo-accent-gradient": [".audio-mute", ".osd-slider", ".audio-slider"],
        "--apollo-success-color": [".kind-success"],
        "--apollo-warning-color": [".kind-warning"],
        "--apollo-danger-color": [".kind-error", ".dock-icon"],
        "--apollo-bar-color": ["#sidebar", ".sidebar-clock-badge"],
        "--apollo-bar-gradient": ["#sidebar"],
        "--apollo-bar-opacity": ["#sidebar"],
        "--apollo-bar-text-color": [".sidebar-clock", ".sidebar-clock-badge"],
        "--apollo-clock-color": [".sidebar-clock", ".sidebar-clock-badge"],
        "--apollo-bar-icon-color": [".sidebar-icon", ".space-mark"],
        "--apollo-spaces-active-color": [".space-mark"],
        "--apollo-bar-width": ["#sidebar"],
        "--apollo-bar-radius": ["#sidebar"],
        "--apollo-fusion-radius": ["#sidebar"],
        "--apollo-bar-padding": [".sidebar-modules"],
        "--apollo-bar-item-spacing": [".sidebar-modules"],
        "--apollo-dock-icon-size": [".dock-item"],
        "--apollo-dock-spacing": [".dock"],
        "--apollo-dock-indicator-color": [".dock-running-dot"],
        "--apollo-panel-color": panels,
        "--apollo-panel-gradient": panels,
        "--apollo-panel-opacity": panels,
        "--apollo-panel-radius": panels,
        "--apollo-card-color": cards + [".osd-slider", ".audio-slider"],
        "--apollo-card-gradient": cards + [".osd-slider", ".audio-slider"],
        "--apollo-card-radius": cards + [".card-media-artwork", ".media-artwork", ".media-artwork-image", ".media-empty-badge", ".media-tab", ".card-media-strip-cover", ".card-media-strip-art", ".perf-card", ".perf-hero", ".perf-storage", ".perf-memory", ".perf-network", ".perf-battery"],
        "--apollo-launcher-highlight-color": [".launcher-row"],
        "--apollo-launcher-highlight-gradient": [".launcher-row"],
        "--apollo-launcher-row-height": [".launcher-row"],
        "--apollo-control-radius": [".launcher-", ".toast-chip", ".audio-"],
        "--apollo-toast-color": [".toast-card"],
        "--apollo-toast-gradient": [".toast-card"],
        "--apollo-toast-text-color": [".toast-card"],
        "--apollo-toast-radius": [".toast-card"],
    ]

    static func matches(_ part: String, place: String) -> Bool {
        let regex = try! NSRegularExpression(pattern: #"[.#][A-Za-z0-9_-]+|:root"#)
        let tokens = regex.matches(in: part, range: NSRange(part.startIndex..., in: part)).map { String(part[Range($0.range, in: part)!]) }
        return tokens.contains { place.hasSuffix("-") ? $0.hasPrefix(place) : $0 == place }
    }

    static func tokenPlaces(in css: String) -> [(selector: String, token: String)] {
        var text = css
        while let start = text.range(of: "/*"), let end = text.range(of: "*/", range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound..<end.upperBound)
        }
        let regex = try! NSRegularExpression(pattern: #"var\(\s*(--apollo-[a-z-]+)"#)
        var result: [(String, String)] = []
        for block in text.components(separatedBy: "}") {
            let parts = block.components(separatedBy: "{")
            guard parts.count == 2 else { continue }
            let selector = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let body = parts[1]
            for match in regex.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                result.append((selector, String(body[Range(match.range(at: 1), in: body)!])))
            }
        }
        return result
    }

    @Test("Stellenprüfung: jeder Teil-Selektor einzeln, Klassen exakt oder per Präfix mit Bindestrich")
    func placeMatching() {
        #expect(Self.matches(".card", place: ".card"))
        #expect(!Self.matches(".card-media-title", place: ".card"))
        #expect(Self.matches(".weather-place:checked", place: ".weather-place"))
        #expect(!Self.matches(".weather-place-name", place: ".weather-place"))
        #expect(Self.matches("#dashboard .card-x", place: "#dashboard"))
        #expect(Self.matches(".launcher-row", place: ".launcher-"))
        let parts = ".osd-percent, .card-media-title".components(separatedBy: ",")
        #expect(!parts.allSatisfy { part in Self.allowedPlaces["--apollo-on-accent-color"]!.contains { Self.matches(part, place: $0) } })
    }

    static let readTokens: Set<String> = [
        "--apollo-panel-fill", "--apollo-bar-fill", "--apollo-card-fill", "--apollo-toast-fill", "--apollo-launcher-highlight-fill",
        "--apollo-text-color", "--apollo-secondary-text-color", "--apollo-muted-text-color", "--apollo-accent-color", "--apollo-on-accent-color",
        "--apollo-separator-color", "--apollo-danger-color", "--apollo-success-color", "--apollo-warning-color",
        "--apollo-panel-radius", "--apollo-card-radius", "--apollo-control-radius", "--apollo-toast-radius", "--apollo-toast-text-color",
        "--apollo-bar-text-color", "--apollo-bar-icon-color", "--apollo-clock-color", "--apollo-spaces-active-color", "--apollo-bar-width",
    ]

    @Test("style.css liest nur Theme-Tokens, die es gibt, jeden mit Liquid-Glass-Vorgabe, und die tragenden alle")
    func tokenPlaces() throws {
        let css = try String(contentsOf: Self.defaultFolder.appendingPathComponent("style.css"), encoding: .utf8)
        let known = Set(ThemeTokenCatalog.standard.tokens.map(\.name)).union(Self.derived.keys)
        let used = Set(Self.tokenPlaces(in: css).map(\.token))
        for token in used { #expect(known.contains(token), "\(token) ist kein Theme-Token") }
        #expect(used.isSuperset(of: Self.readTokens), "nicht gelesen: \(Self.readTokens.subtracting(used).sorted())")
        let bare = try NSRegularExpression(pattern: #"var\(\s*--apollo-[a-z-]+\s*\)"#)
        #expect(bare.numberOfMatches(in: css, range: NSRange(css.startIndex..., in: css)) == 0, "jeder Token braucht eine Vorgabe ohne Theme")
    }

    @Test("Apples Menüleiste bleibt: die Default-Config hat keine eigene und blendet Apples nicht aus")
    func menubarDefaults() throws {
        let ir = try #require(PackageResources.load(Self.defaultFolder, id: "apolloshell-default").ir)
        #expect(!ir.surfaces.contains { $0.id.contains("menubar") })
        let files = try FileManager.default.contentsOfDirectory(at: Self.defaultFolder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "kdl" }
        for file in files {
            #expect(!(try String(contentsOf: file, encoding: .utf8)).contains("system.hide-apple-menubar"), "\(file.lastPathComponent)")
        }
    }
}
