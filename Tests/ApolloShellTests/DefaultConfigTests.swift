import Foundation
import Testing
import ApolloBase
import ApolloConfig
import ApolloStyle

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

    @Test("Oberflächen nach default-config.md 3")
    func surfaces() throws {
        let ir = try #require(PackageResources.load(Self.defaultFolder, id: "apolloshell-default").ir)
        let kinds = Dictionary(uniqueKeysWithValues: ir.surfaces.map { ($0.id, $0.kind) })
        let expected = [
            "sidebar": "panel", "desktop-clock": "panel", "dashboard": "popup", "utilities": "popup",
            "launcher": "popup", "session": "popup", "volume": "osd", "default": "toast",
            "onboarding": "window", "settings": "window", "settings-confirm": "popup",
        ]
        #expect(kinds == expected)
    }

    @Test("gespeicherte var nach default-config.md 2")
    func persistedVars() throws {
        let ir = try #require(PackageResources.load(Self.defaultFolder, id: "apolloshell-default").ir)
        let persisted = Set(ir.vars.filter(\.persist).map(\.name))
        let expected: Set<String> = [
            "sidebar-modules", "sidebar-screens", "sidebar-background", "dashboard-tabs",
            "dashboard-cards-top", "dashboard-cards-bottom", "dashboard-cards-side", "utilities-cards",
            "utilities-toggles", "weather-source", "weather-places", "weather-selected", "file-manager",
            "toast-charging", "toast-battery", "toast-audio-output", "toast-audio-input", "desktop-clock",
            "hotkey-launcher", "hotkey-dashboard", "hotkey-utilities", "hotkey-settings", "hide-apple-dock",
            "keep-awake-lid", "onboarding-done",
        ]
        #expect(persisted == expected)
    }

    struct Assignment {
        var prefix: String
        var range: ClosedRange<Int>
        var artifacts: [String]
    }

    static let assignments: [Assignment] = [
        Assignment(prefix: "SB", range: 1...15, artifacts: ["define:sidebar-dashboard-button", "define:sidebar-spaces", "define:sidebar-dock", "define:sidebar-clock", "define:sidebar-utilities-button", "define:sidebar-status-icons", "define:sidebar-power", "define:sidebar-spacer", "define:sidebar-gap", "define:sidebar-divider", "define:sidebar-app-button", "define:sidebar-battery", "define:sidebar-cpu", "define:sidebar-weather", "define:sidebar-media-button"]),
        Assignment(prefix: "SB", range: 16...22, artifacts: ["surface:sidebar", "var:sidebar-background", "var:sidebar-screens", "var:status-popout"]),
        Assignment(prefix: "SP", range: 1...19, artifacts: ["define:popout-wifi", "define:popout-bluetooth", "define:popout-battery"]),
        Assignment(prefix: "DC", range: 1...5, artifacts: ["surface:desktop-clock", "var:desktop-clock"]),
        Assignment(prefix: "SW", range: 1...4, artifacts: ["define:sidebar-spaces"]),
        Assignment(prefix: "ED", range: 1...17, artifacts: ["surface:dashboard", "surface:utilities", "surface:launcher", "surface:session", "surface:volume"]),
        Assignment(prefix: "SS", range: 1...3, artifacts: ["surface:sidebar"]),
        Assignment(prefix: "DK", range: 1...39, artifacts: ["define:dock-item", "define:sidebar-dock", "var:dock-first-running"]),
        Assignment(prefix: "AD", range: 1...10, artifacts: ["var:hide-apple-dock"]),
        Assignment(prefix: "LA", range: 1...25, artifacts: ["surface:launcher", "var:hotkey-launcher", "var:launcher-results"]),
        Assignment(prefix: "LA", range: 26...27, artifacts: ["config:launcher-only"]),
        Assignment(prefix: "MP", range: 1...24, artifacts: ["shell"]),
        Assignment(prefix: "DB", range: 1...41, artifacts: ["surface:dashboard", "define:dashboard-overview", "define:dashboard-media", "define:dashboard-performance", "define:dashboard-weather", "define:card-weather", "define:card-user", "define:card-clock", "define:card-calendar", "define:card-resources", "define:card-media", "var:dashboard-tabs"]),
        Assignment(prefix: "UT", range: 1...34, artifacts: ["surface:utilities", "define:card-keep-awake", "define:card-audio", "define:card-quick-toggles", "var:utilities-cards", "var:utilities-toggles", "define:settings-page-control-centre"]),
        Assignment(prefix: "KA", range: 1...12, artifacts: ["define:card-keep-awake", "var:keep-awake-lid"]),
        Assignment(prefix: "OB", range: 1...9, artifacts: ["surface:onboarding", "var:onboarding-done", "define:settings-page-about"]),
        Assignment(prefix: "NX", range: 1...32, artifacts: ["surface:settings", "define:settings-page-general", "define:settings-page-shortcuts", "define:settings-page-sidebar", "define:settings-page-control-centre", "define:settings-page-launcher", "define:settings-page-dashboard", "define:settings-page-desktop", "define:settings-page-toasts", "define:settings-page-providers", "define:settings-page-system-settings", "define:settings-page-about"]),
        Assignment(prefix: "SM", range: 1...21, artifacts: ["surface:session", "define:session-button"]),
        Assignment(prefix: "OSD", range: 1...8, artifacts: ["surface:volume", "var:osd-moving"]),
        Assignment(prefix: "TO", range: 1...17, artifacts: ["surface:default", "define:toast-card", "var:toast-charging", "var:toast-battery", "var:toast-audio-output", "var:toast-audio-input"]),
        Assignment(prefix: "HK", range: 1...16, artifacts: ["var:hotkey-launcher", "var:hotkey-dashboard", "var:hotkey-utilities", "var:hotkey-settings", "define:settings-page-shortcuts"]),
        Assignment(prefix: "WG", range: 1...16, artifacts: ["surface:sidebar"]),
        Assignment(prefix: "FS", range: 1...7, artifacts: ["surface:sidebar"]),
        Assignment(prefix: "MS", range: 1...9, artifacts: ["var:sidebar-screens"]),
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
        let ir = try #require(PackageResources.load(Self.defaultFolder, id: "apolloshell-default").ir)
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
        let presets = try String(contentsOf: Self.defaultFolder.appendingPathComponent("presets.kdl"), encoding: .utf8)
        for name in Self.presetLets.values.flatMap({ $0 }) + ["hotkeys-default", "hotkeys-hyper"] {
            #expect(presets.contains("let \(name) {"), "\(name)")
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

    static let cards = [".card", ".card-weather", ".card-user", ".card-clock", ".card-calendar", ".card-resources", ".card-media", ".media-source", ".popout-card", ".utilities-card", ".onboarding-card"]
    static let panels = ["#dashboard", "#utilities", "#launcher", "#session"]

    static let allowedPlaces: [String: [String]] = [
        "--apollo-separator-color": [".launcher-separator"],
        "--apollo-border-color": cards,
        "--apollo-border-width": cards,
        "--apollo-shadow-opacity": [".audio-mute", ".osd-slider", ".audio-slider"],
        "--apollo-text-color": [".launcher-"],
        "--apollo-secondary-text-color": [".launcher-"],
        "--apollo-on-accent-color": [".space-number", ".popout-status-circle", ".popout-capsule", ".dashboard-tab", ".card-user-avatar", ".card-calendar-day", ".media-play", ".perf-badge-text", ".weather-place", ".audio-mute", ".quick-toggle", ".osd-slider", ".toast-chip", ".audio-slider", ".keep-awake-chip"],
        "--apollo-accent-color": [":root", ".space-pill", ".popout-status-circle", ".popout-capsule", ".popout-battery-bolt", ".dashboard-tab-pill", ".card-user-avatar", ".card-calendar-day", ".media-play", ".perf-graph", ".perf-badge-shape", ".weather-place", ".audio-mute", ".audio-slider", ".quick-toggle", ".session-mark", ".osd-slider", ".toast-chip", ".onboarding-dot", ".keep-awake-chip", ".dashboard-tab", ".card-resource-ring", ".card-media-arc", ".media-empty-badge", ".media-timeline", ".card-media-bar"],
        "--apollo-accent-gradient": [".audio-mute", ".osd-slider", ".audio-slider"],
        "--apollo-success-color": [".kind-success"],
        "--apollo-warning-color": [".kind-warning"],
        "--apollo-danger-color": [".kind-error", ".dock-icon"],
        "--apollo-bar-color": ["#sidebar"],
        "--apollo-bar-gradient": ["#sidebar"],
        "--apollo-bar-opacity": ["#sidebar"],
        "--apollo-bar-text-color": [".sidebar-clock"],
        "--apollo-bar-icon-color": [".sidebar-icon"],
        "--apollo-bar-width": ["#sidebar"],
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
        "--apollo-card-radius": cards + [".card-media-artwork", ".media-artwork", ".media-artwork-image", ".media-empty-badge", ".media-tab", ".card-media-strip-cover", ".card-media-strip-art", ".perf-card"],
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

    @Test("Token-Stellen wie anhang-token-verbraucher.md")
    func tokenPlaces() throws {
        let css = try String(contentsOf: Self.defaultFolder.appendingPathComponent("style.css"), encoding: .utf8)
        var used: Set<String> = []
        for (selector, token) in Self.tokenPlaces(in: css) {
            let bases = Self.derived[token] ?? [token]
            for base in bases {
                used.insert(base)
                guard let places = Self.allowedPlaces[base] else {
                    Issue.record("\(token) an '\(selector)' hat in 0.1.4.2 keinen Leser dort (Basis \(base))")
                    continue
                }
                let allowed = selector.components(separatedBy: ",").allSatisfy { part in
                    places.contains { Self.matches(part, place: $0) }
                }
                #expect(allowed, "\(token) an '\(selector)' ist keine Stelle aus 0.1.4.2")
            }
        }
        let missing = Set(Self.allowedPlaces.keys).subtracting(used)
        #expect(missing.isEmpty, "nicht gelesen: \(missing.sorted())")
    }
}
