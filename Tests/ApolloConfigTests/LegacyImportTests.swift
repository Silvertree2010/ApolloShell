import Testing
import Foundation
import ApolloBase
@testable import ApolloConfig

enum LegacyFixtures {
    static let folder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/legacy-0.1.4.2")

    static func text(_ name: String) throws -> String {
        try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
    }

    static func convert(settings: String? = nil, weather: String? = nil, launcherOnly: Bool = false) throws -> LegacyImportResult {
        var counter = 0
        return LegacyImport.convert(
            settings: try settings.map(text),
            weather: try weather.map(text),
            launcherOnly: launcherOnly,
            makeID: {
                counter += 1
                return "00000000-0000-0000-0000-00000000000\(counter)"
            }
        )
    }

    static func record(_ pairs: [(String, Value)]) -> Value {
        .record(Record(pairs))
    }

    static func list(_ value: Value?) -> [Record] {
        guard case .list(let items)? = value else { return [] }
        return items.compactMap { item in
            if case .record(let record) = item { return record }
            return nil
        }
    }

    static func ids(_ value: Value?) -> [String] {
        list(value).compactMap { record in
            if case .string(let id)? = record["id"] { return id }
            if case .string(let kind)? = record["kind"] { return kind }
            return nil
        }
    }

    static func messages(_ result: LegacyImportResult) -> [String] {
        result.diagnostics.map(\.message)
    }

    static func mentions(_ result: LegacyImportResult, _ fragment: String) -> Bool {
        result.diagnostics.contains { $0.message.contains(fragment) }
    }
}

@Suite("Übernahme 0.1.4.2: settings.json mit jedem Schlüssel")
struct LegacyImportFullTests {
    let result: LegacyImportResult

    init() throws {
        result = try LegacyFixtures.convert(settings: "settings-full.json", weather: "weather.json")
    }

    @Test("gültige Datei ergibt keine Diagnose")
    func noDiagnostics() {
        #expect(result.diagnostics.isEmpty, "\(LegacyFixtures.messages(result))")
    }

    @Test("bar.layout → sidebar-modules, Arten und Kennungen kebab-case, workspaces → spaces")
    func sidebarModules() {
        let modules = LegacyFixtures.list(result.state["sidebar-modules"])
        #expect(LegacyFixtures.ids(result.state["sidebar-modules"]) == [
            "dashboard-button", "spaces", "dock", "clock", "utilities-button", "status-icons", "power",
            "spacer", "gap", "gap-2", "divider", "app-button", "battery", "cpu", "weather", "media-button",
        ])
        #expect(modules.map { $0["kind"] } == [
            "dashboard-button", "spaces", "dock", "clock", "utilities-button", "status-icons", "power",
            "spacer", "gap", "gap", "divider", "app-button", "battery", "cpu", "weather", "media-button",
        ].map { Value.string($0) })
    }

    @Test("bar.layout Optionen je Art")
    func sidebarOptions() {
        let modules = Dictionary(uniqueKeysWithValues: LegacyFixtures.list(result.state["sidebar-modules"]).map { record -> (String, Record) in
            guard case .string(let id)? = record["id"] else { return ("", record) }
            return (id, record)
        })
        #expect(modules["spaces"]?["style"] == .string("numbers"))
        #expect(modules["dock"]?["show-running"] == .bool(false))
        #expect(modules["dock"]?["icon-size"] == .string("large"))
        #expect(modules["clock"]?["show-icon"] == .bool(false))
        #expect(modules["clock"]?["show-date"] == .bool(true))
        #expect(modules["status-icons"]?["wifi"] == .bool(false))
        #expect(modules["status-icons"]?["bluetooth"] == .bool(true))
        #expect(modules["status-icons"]?["battery"] == .bool(false))
        #expect(modules["gap"]?["height"] == .number(24))
        #expect(modules["gap-2"]?["height"] == .number(96))
        #expect(modules["app-button"]?["bundle-id"] == .string("com.apple.Safari"))
        #expect(modules["battery"]?["show-icon"] == .bool(false))
        #expect(modules["cpu"]?["style"] == .string("percent"))
        #expect(modules["weather"]?["show-temperature"] == .bool(false))
        #expect(modules["power"]?.keys == ["id", "kind"])
    }

    @Test("bar.screens und bar.background")
    func sidebarScreensAndBackground() {
        #expect(result.state["sidebar-screens"] == .string("DELL U2720Q@3840x2160"))
        #expect(result.state["sidebar-background"] == .string("tinted-glass"))
    }

    @Test("dashboard.tabs → dashboard-tabs")
    func dashboardTabs() {
        let tabs = LegacyFixtures.list(result.state["dashboard-tabs"])
        #expect(tabs.map { $0["id"] } == ["weather", "dashboard", "media", "performance"].map { Value.string($0) })
        #expect(tabs.map { $0["visible"] } == [true, true, false, false].map { Value.bool($0) })
    }

    @Test("dashboard.cards → drei Zonen mit Optionen")
    func dashboardCards() {
        #expect(LegacyFixtures.ids(result.state["dashboard-cards-top"]) == ["media", "resources"])
        #expect(LegacyFixtures.ids(result.state["dashboard-cards-bottom"]) == ["calendar", "clock"])
        #expect(LegacyFixtures.ids(result.state["dashboard-cards-side"]) == ["weather"])
        let top = LegacyFixtures.list(result.state["dashboard-cards-top"])
        #expect(top[0]["show-album"] == .bool(false))
        #expect(top[1]["show-cpu"] == .bool(true))
        #expect(top[1]["show-memory"] == .bool(false))
        let bottom = LegacyFixtures.list(result.state["dashboard-cards-bottom"])
        #expect(bottom[0]["first-weekday"] == .string("sunday"))
        #expect(bottom[0]["show-week-numbers"] == .bool(true))
        #expect(bottom[1]["style"] == .string("inline"))
        #expect(bottom[1]["kind"] == .string("clock"))
        let side = LegacyFixtures.list(result.state["dashboard-cards-side"])
        #expect(side[0]["show-condition"] == .bool(false))
    }

    @Test("utilities.layout.cards → utilities-cards")
    func utilitiesCards() {
        let cards = LegacyFixtures.list(result.state["utilities-cards"])
        #expect(cards.map { $0["kind"] } == ["quick-toggles", "keep-awake", "audio"].map { Value.string($0) })
        #expect(cards.map { $0["enabled"] } == [true, false, true].map { Value.bool($0) })
    }

    @Test("utilities.layout.quickToggles → utilities-toggles mit Optionen, leere Texte = automatisch")
    func utilitiesToggles() {
        let toggles = LegacyFixtures.list(result.state["utilities-toggles"])
        #expect(LegacyFixtures.ids(result.state["utilities-toggles"]) == ["dark-mode", "hide-apps", "open-app", "open-link", "run-shortcut", "open-app-2"])
        #expect(toggles[1]["keep-frontmost"] == .bool(true))
        #expect(toggles[2]["bundle-id"] == .string("com.apple.Music"))
        #expect(toggles[2]["title"] == .string("Musik"))
        #expect(toggles[2]["symbol"] == nil)
        #expect(toggles[3]["url"] == .string("https://apollocloud.to"))
        #expect(toggles[3]["symbol"] == .string("globe"))
        #expect(toggles[3]["title"] == nil)
        #expect(toggles[4]["name"] == .string("Focus On"))
        #expect(toggles[4]["identifier"] == .string("3C1E2F0A-8B7D-4E7A-9C41-2F0B6D1E5A77"))
        #expect(toggles[5]["bundle-id"] == .string(""))
        #expect(toggles[5].keys == ["id", "kind", "bundle-id"])
    }

    @Test("providers.weather und providers.fileManager")
    func providers() {
        #expect(result.state["weather-source"] == .string("met-norway"))
        #expect(result.state["file-manager"] == .string("com.binarynights.ForkLift"))
    }

    @Test("toasts.* → toast-*")
    func toasts() {
        #expect(result.state["toast-charging"] == .bool(true))
        #expect(result.state["toast-battery"] == .bool(false))
        #expect(result.state["toast-audio-output"] == .bool(true))
        #expect(result.state["toast-audio-input"] == .bool(false))
    }

    @Test("background.desktopClock → desktop-clock")
    func desktopClock() {
        #expect(result.state["desktop-clock"] == .bool(false))
    }

    @Test("hotKeys → hotkey-*, null = kein Kürzel")
    func hotKeys() {
        #expect(result.state["hotkey-launcher"] == .string("cmd+space"))
        #expect(result.state["hotkey-dashboard"] == .string("ctrl+shift+d"))
        #expect(result.state["hotkey-utilities"] == .string("hyper+u"))
        #expect(result.state["hotkey-settings"] == .string(""))
    }

    @Test("appleDockHiding, keepAwake, onboarding")
    func flags() {
        #expect(result.state["hide-apple-dock"] == .bool(false))
        #expect(result.state["keep-awake-lid"] == .bool(false))
        #expect(result.state["onboarding-done"] == .bool(false))
    }

    @Test("theme.name → theme")
    func theme() {
        #expect(result.theme == "Catppuccin Mocha")
    }

    @Test("weather.json favorites/selectedID → weather-places/weather-selected")
    func weather() {
        let places = LegacyFixtures.list(result.state["weather-places"])
        #expect(places.count == 2)
        #expect(places[0] == Record([("id", .string("5B1E7C9A-2D4F-4A6B-8C0D-1E2F3A4B5C6D")), ("name", .string("Chur")), ("latitude", .number(46.85)), ("longitude", .number(9.53))]))
        #expect(result.state["weather-selected"] == .string("0F9E8D7C-6B5A-4948-3726-15040A0B0C0D"))
    }

    @Test("nur Schlüssel aus default-config.md 2, sonst nichts")
    func onlyKnownVars() {
        let expected: Set<String> = [
            "sidebar-modules", "sidebar-screens", "sidebar-background", "dashboard-tabs",
            "dashboard-cards-top", "dashboard-cards-bottom", "dashboard-cards-side", "utilities-cards",
            "utilities-toggles", "weather-source", "weather-places", "weather-selected", "file-manager",
            "toast-charging", "toast-battery", "toast-audio-output", "toast-audio-input", "desktop-clock",
            "hotkey-launcher", "hotkey-dashboard", "hotkey-utilities", "hotkey-settings", "hide-apple-dock",
            "keep-awake-lid", "onboarding-done",
        ]
        #expect(Set(result.state.keys) == expected)
    }
}

@Suite("Übernahme 0.1.4.2: kaputte Werte")
struct LegacyImportBrokenTests {
    let result: LegacyImportResult

    init() throws {
        result = try LegacyFixtures.convert(settings: "settings-broken.json", weather: "weather-broken.json")
    }

    @Test("jede Diagnose ist eine Warnung mit Dateiname und Hinweis auf die Vorgabe")
    func diagnosticsShape() {
        #expect(!result.diagnostics.isEmpty)
        for diagnostic in result.diagnostics {
            #expect(diagnostic.severity == .warning)
            #expect(diagnostic.message.hasPrefix("settings-broken.json: ") || diagnostic.message.hasPrefix("weather-broken.json: ") || diagnostic.message.hasPrefix("settings.json: ") || diagnostic.message.hasPrefix("weather.json: "))
            #expect(diagnostic.help != nil)
        }
    }

    @Test("falsche Typen bei Schaltern werden übersprungen und gemeldet")
    func wrongScalarTypes() {
        for name in ["hide-apple-dock", "desktop-clock", "keep-awake-lid", "onboarding-done", "toast-charging", "toast-audio-output", "toast-audio-input"] {
            #expect(result.state[name] == nil, "\(name)")
        }
        #expect(result.state["toast-battery"] == .bool(false))
        for fragment in ["appleDockHiding.hideWhileRunning", "background.desktopClock", "'keepAwake' is not an object", "onboarding.completed", "toasts.chargingChanged", "toasts.audioOutputChanged", "toasts.audioInputChanged"] {
            #expect(LegacyFixtures.mentions(result, fragment), "\(fragment)")
        }
    }

    @Test("unbekannte Werte in Aufzählungen werden übersprungen")
    func unknownEnumValues() {
        #expect(result.state["sidebar-background"] == nil)
        #expect(result.state["sidebar-screens"] == nil)
        #expect(result.state["weather-source"] == nil)
        #expect(result.state["file-manager"] == nil)
        #expect(result.theme == nil)
        for fragment in ["bar.background", "bar.screens", "providers.weather", "providers.fileManager", "theme.name"] {
            #expect(LegacyFixtures.mentions(result, fragment), "\(fragment)")
        }
    }

    @Test("Sidebar: unbekannte Bausteine und doppelte einzigartige fallen weg, kaputte Optionen = Vorgabe")
    func sidebar() {
        let modules = LegacyFixtures.list(result.state["sidebar-modules"])
        #expect(LegacyFixtures.ids(result.state["sidebar-modules"]) == ["dock", "gap", "clock"])
        #expect(modules[0]["icon-size"] == .string("medium"))
        #expect(modules[0]["show-running"] == .bool(true))
        #expect(modules[1]["height"] == .number(16))
        #expect(modules[2]["show-icon"] == .bool(true))
        for fragment in ["unknown kind 'rocketLauncher'", "repeats 'dock'", "'bar.layout[3]' is not an object", "iconSize", "showRunning", "height", "'bar.layout[5].options' is not an object"] {
            #expect(LegacyFixtures.mentions(result, fragment), "\(fragment)")
        }
    }

    @Test("Dashboard: unbekannter Reiter weg, alle versteckt → erster sichtbar")
    func dashboardTabs() {
        let tabs = LegacyFixtures.list(result.state["dashboard-tabs"])
        #expect(tabs.map { $0["id"] } == ["media", "dashboard", "weather", "performance"].map { Value.string($0) })
        #expect(tabs.map { $0["visible"] } == [true, false, false, false].map { Value.bool($0) })
        #expect(LegacyFixtures.mentions(result, "dashboard.tabs[1]"))
    }

    @Test("Dashboard-Karten: kaputte Zone = Vorgabe, doppelte und unerlaubte fallen weg, Ressourcen ohne Ring = alle")
    func dashboardCards() {
        #expect(LegacyFixtures.ids(result.state["dashboard-cards-top"]) == ["weather", "user"])
        #expect(LegacyFixtures.ids(result.state["dashboard-cards-bottom"]) == ["calendar", "resources"])
        #expect(LegacyFixtures.ids(result.state["dashboard-cards-side"]) == ["media"])
        let resources = LegacyFixtures.list(result.state["dashboard-cards-bottom"])[1]
        #expect(resources["show-cpu"] == .bool(true))
        #expect(resources["show-memory"] == .bool(true))
        #expect(resources["show-storage"] == .bool(true))
        #expect(LegacyFixtures.mentions(result, "'dashboard.cards.top' is not a list"))
        #expect(LegacyFixtures.mentions(result, "card 'calendar' does not fit 'dashboard.cards.side'"))
    }

    @Test("Kontrollzentrum: unbekannte Karte weg, fehlende angehängt, doppelte Schalter weg")
    func utilities() {
        let cards = LegacyFixtures.list(result.state["utilities-cards"])
        #expect(cards.map { $0["kind"] } == ["audio", "keep-awake", "quick-toggles"].map { Value.string($0) })
        #expect(cards.map { $0["enabled"] } == [true, true, true].map { Value.bool($0) })
        #expect(LegacyFixtures.ids(result.state["utilities-toggles"]) == ["wifi", "open-app"])
        let app = LegacyFixtures.list(result.state["utilities-toggles"])[1]
        #expect(app["bundle-id"] == .string(""))
        #expect(app["title"] == nil)
        for fragment in ["cards[1]", "repeats 'wifi'", "unknown kind 'teleport'", "options.bundleID", "options.title"] {
            #expect(LegacyFixtures.mentions(result, fragment), "\(fragment)")
        }
    }

    @Test("Tastenkürzel: kaputte übersprungen, fehlendes = Vorgabe der frischen Installation wie 0.1.4.2")
    func hotKeys() {
        #expect(result.state["hotkey-launcher"] == nil)
        #expect(result.state["hotkey-dashboard"] == nil)
        #expect(result.state["hotkey-utilities"] == nil)
        #expect(result.state["hotkey-settings"] == .string("ctrl+alt+comma"))
        #expect(LegacyFixtures.mentions(result, "'hotKeys.launcher' is not a shortcut"))
        #expect(LegacyFixtures.mentions(result, "'hotKeys.dashboard' is not a shortcut"))
        #expect(LegacyFixtures.mentions(result, "key code 10"))
    }

    @Test("weather.json: kaputte Orte fallen weg, fehlende Kennung wird erzeugt, unbekannte Auswahl → erster")
    func weather() {
        let places = LegacyFixtures.list(result.state["weather-places"])
        #expect(places.count == 1)
        #expect(places[0]["id"] == .string("00000000-0000-0000-0000-000000000001"))
        #expect(places[0]["name"] == .string("Bad Ragaz"))
        #expect(result.state["weather-selected"] == .string("00000000-0000-0000-0000-000000000001"))
        for fragment in ["favorites[0].id", "favorites[1]", "favorites[2]", "selectedID"] {
            #expect(LegacyFixtures.mentions(result, fragment), "\(fragment)")
        }
    }
}

@Suite("Übernahme 0.1.4.2: Randfälle")
struct LegacyImportEdgeTests {
    @Test("kein JSON: nichts übernommen, eine Diagnose")
    func notJSON() throws {
        let result = try LegacyFixtures.convert(settings: "settings-truncated.json")
        #expect(result.state.isEmpty)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].message.contains("could not be read as JSON"))
    }

    @Test("JSON, aber kein Objekt: nichts übernommen")
    func notAnObject() {
        let result = LegacyImport.convert(settings: "[1, 2]", weather: "\"x\"", launcherOnly: false)
        #expect(result.state.isEmpty)
        #expect(result.diagnostics.count == 2)
    }

    @Test("fehlende Abschnitte: kein Wert, die Vorgabe der bestehenden Installation greift")
    func missingSections() {
        let result = LegacyImport.convert(settings: "{}", weather: nil, launcherOnly: false)
        #expect(result.state.isEmpty)
        #expect(result.diagnostics.isEmpty)
        #expect(result.theme == nil)
    }

    @Test("Abschnitt ohne Objekt wird gemeldet")
    func sectionNotObject() {
        let result = LegacyImport.convert(settings: #"{"bar": 3, "hotKeys": []}"#, weather: nil, launcherOnly: false)
        #expect(result.state.isEmpty)
        #expect(result.diagnostics.count == 2)
    }

    @Test("alte einzeilige weather.json wird ein Favorit")
    func singleLocationWeather() throws {
        let result = try LegacyFixtures.convert(weather: "weather-single.json")
        let places = LegacyFixtures.list(result.state["weather-places"])
        #expect(places.count == 1)
        #expect(places[0]["name"] == .string("Location"))
        #expect(result.state["weather-selected"] == places[0]["id"])
    }

    @Test("Nur-Launcher wird durchgereicht, Schlüssel und Altschlüssel wie 0.1.4.2")
    func launcherOnlyFlag() {
        #expect(LegacyImport.convert(settings: nil, weather: nil, launcherOnly: true).launcherOnly)
        let defaults: [[String: Any]] = [["launcherOnly": true], ["nurLauncher": "yes"], ["launcherOnly": false, "nurLauncher": true], [:]]
        let expected = [true, true, false, false]
        for (values, flag) in zip(defaults, expected) {
            let paths = ConfigPaths(builtinConfigs: URL(fileURLWithPath: "/b"), userConfig: URL(fileURLWithPath: "/u"), applicationSupport: URL(fileURLWithPath: "/a"))
            let fs = MemoryFileSystem(["/a/settings.json": "{}"])
            let result = LegacyImport.run(paths: paths, fileSystem: fs, defaults: { values[$0] })
            #expect(result.launcherOnly == flag)
        }
    }

    @Test("kebab-case wie default-config.md: dashboardButton, showCPU, bundleID")
    func kebab() {
        #expect(LegacyImport.kebab("dashboardButton") == "dashboard-button")
        #expect(LegacyImport.kebab("showCPU") == "show-cpu")
        #expect(LegacyImport.kebab("bundleID") == "bundle-id")
        #expect(LegacyImport.kebab("power") == "power")
        #expect(LegacyImport.renamedID("workspaces-3", kinds: LegacyImport.sidebarKinds) == "spaces-3")
        #expect(LegacyImport.renamedID("appButton-2", kinds: LegacyImport.sidebarKinds) == "app-button-2")
    }
}

@Suite("Übernahme 0.1.4.2: Dateien")
struct LegacyImportFileTests {
    static func paths(_ root: URL) -> ConfigPaths {
        ConfigPaths(
            builtinConfigs: root.appendingPathComponent("builtin"),
            userConfig: root.appendingPathComponent("config"),
            applicationSupport: root.appendingPathComponent("Application Support/ApolloShell")
        )
    }

    static func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("schreibt state und settings.kdl, alte Dateien bleiben byte-gleich")
    func writesAndLeavesOldFiles() throws {
        let root = try Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = Self.paths(root)
        try FileManager.default.createDirectory(at: paths.applicationSupport, withIntermediateDirectories: true)
        var before: [String: (Data, Date)] = [:]
        for (source, target) in [("settings-full.json", "settings.json"), ("weather.json", "weather.json")] {
            let url = paths.applicationSupport.appendingPathComponent(target)
            try FileManager.default.copyItem(at: LegacyFixtures.folder.appendingPathComponent(source), to: url)
            let date = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date ?? .distantPast
            before[target] = (try Data(contentsOf: url), date)
        }
        let fs = DiskFileSystem()
        #expect(LegacyImport.isNeeded(paths: paths, fileSystem: fs))

        let result = LegacyImport.run(paths: paths, fileSystem: fs, defaults: { $0 == "nurLauncher" ? true : nil })

        #expect(result.diagnostics.isEmpty, "\(LegacyFixtures.messages(result))")
        for (name, (data, date)) in before {
            let url = paths.applicationSupport.appendingPathComponent(name)
            #expect(try Data(contentsOf: url) == data, "\(name)")
            let after = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
            #expect(after == date, "\(name)")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.applicationSupport.path).sorted() == ["settings.json", "weather.json"])

        let stateText = try String(contentsOf: LegacyImport.stateFile(paths), encoding: .utf8)
        let (values, diagnostics) = VarStateFile.readAll(stateText, file: "state.kdl")
        #expect(diagnostics.isEmpty)
        #expect(values == result.state)

        let settingsText = try String(contentsOf: paths.settingsFile, encoding: .utf8)
        let (settings, settingsDiagnostics) = ShellSettingsFile.parse(settingsText, file: "settings.kdl")
        #expect(settingsDiagnostics.isEmpty)
        #expect(settings.theme == "Catppuccin Mocha")
        #expect(settings.config == "launcher-only")

        let launcherText = try String(contentsOf: LegacyImport.launcherOnlyStateFile(paths), encoding: .utf8)
        let (launcherValues, launcherDiagnostics) = VarStateFile.readAll(launcherText, file: "launcher-only.kdl")
        #expect(launcherDiagnostics.isEmpty)
        #expect(launcherValues == ["hotkey-launcher": try #require(result.state["hotkey-launcher"])])

        #expect(!LegacyImport.isNeeded(paths: paths, fileSystem: fs))
    }

    @Test("ohne settings.json oder mit state-Ordner keine Übernahme")
    func onlyOnce() {
        let paths = Self.paths(URL(fileURLWithPath: "/r"))
        #expect(!LegacyImport.isNeeded(paths: paths, fileSystem: MemoryFileSystem([:])))
        #expect(!LegacyImport.isNeeded(paths: paths, fileSystem: MemoryFileSystem([
            "/r/Application Support/ApolloShell/settings.json": "{}",
            "/r/config/state/other.kdl": "",
        ])))
        #expect(LegacyImport.isNeeded(paths: paths, fileSystem: MemoryFileSystem([
            "/r/Application Support/ApolloShell/settings.json": "{}",
        ])))
    }

    @Test("leere Übernahme legt den state-Ordner trotzdem an, settings.kdl bleibt unberührt")
    func emptyImportMarksDone() {
        let paths = Self.paths(URL(fileURLWithPath: "/r"))
        let fs = MemoryFileSystem(["/r/Application Support/ApolloShell/settings.json": "{}"])
        _ = LegacyImport.run(paths: paths, fileSystem: fs, defaults: { _ in nil })
        #expect(fs.exists(LegacyImport.stateFile(paths)))
        #expect(!fs.exists(LegacyImport.launcherOnlyStateFile(paths)))
        #expect(!fs.exists(paths.settingsFile))
        #expect(!LegacyImport.isNeeded(paths: paths, fileSystem: fs))
    }

    @Test("vorhandene Wahl in settings.kdl wird nicht überschrieben")
    func keepsExistingSettings() throws {
        let paths = Self.paths(URL(fileURLWithPath: "/r"))
        let existing = "theme \"Nord\"\nconfig \"user\"\n"
        let fs = MemoryFileSystem([
            "/r/Application Support/ApolloShell/settings.json": #"{"theme": {"name": "Catppuccin Mocha"}}"#,
            paths.settingsFile.path: existing,
        ])
        _ = LegacyImport.run(paths: paths, fileSystem: fs, defaults: { $0 == "launcherOnly" ? true : nil })
        #expect(try fs.read(paths.settingsFile) == existing)
    }
}
