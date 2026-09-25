import Foundation
import ApolloBase
import ApolloShellCore

public struct LegacyImportResult: Sendable, Hashable {
    public var state: [String: Value]
    public var theme: String?
    public var launcherOnly: Bool
    public var diagnostics: [Diagnostic]

    public init(state: [String: Value] = [:], theme: String? = nil, launcherOnly: Bool = false, diagnostics: [Diagnostic] = []) {
        self.state = state
        self.theme = theme
        self.launcherOnly = launcherOnly
        self.diagnostics = diagnostics
    }
}

public enum LegacyImport {
    public static let configID = "apolloshell-default"
    public static let launcherOnlyConfigID = "launcher-only"

    public static func settingsJSON(_ paths: ConfigPaths) -> URL {
        paths.applicationSupport.appendingPathComponent("settings.json")
    }

    public static func weatherJSON(_ paths: ConfigPaths) -> URL {
        paths.applicationSupport.appendingPathComponent("weather.json")
    }

    public static func stateFile(_ paths: ConfigPaths) -> URL {
        paths.stateDirectory.appendingPathComponent("\(configID).kdl")
    }

    public static func launcherOnlyStateFile(_ paths: ConfigPaths) -> URL {
        paths.stateDirectory.appendingPathComponent("\(launcherOnlyConfigID).kdl")
    }

    public static func isNeeded(paths: ConfigPaths, fileSystem: any ConfigFileSystem) -> Bool {
        fileSystem.exists(settingsJSON(paths)) && !fileSystem.exists(paths.stateDirectory)
    }

    public static func freshInstallFile(_ paths: ConfigPaths) -> URL {
        paths.applicationSupport.appendingPathComponent("fresh-install")
    }

    public static func freshInstall(paths: ConfigPaths, fileSystem: any ConfigFileSystem) -> Bool {
        let file = freshInstallFile(paths)
        if fileSystem.exists(file), let text = try? fileSystem.read(file) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        }
        let fresh = !fileSystem.exists(settingsJSON(paths)) && !fileSystem.exists(paths.stateDirectory)
        try? fileSystem.write(fresh ? "true\n" : "false\n", to: file)
        return fresh
    }

    public static func run(
        paths: ConfigPaths,
        fileSystem: any ConfigFileSystem,
        defaults: (String) -> Any?,
        makeID: () -> String = { UUID().uuidString }
    ) -> LegacyImportResult {
        let settingsURL = settingsJSON(paths)
        let weatherURL = weatherJSON(paths)
        let settingsText = fileSystem.exists(settingsURL) ? try? fileSystem.read(settingsURL) : nil
        let weatherText = fileSystem.exists(weatherURL) ? try? fileSystem.read(weatherURL) : nil
        var result = convert(
            settings: settingsText,
            weather: weatherText,
            launcherOnly: LauncherOnlyFlag.isOn(defaults),
            settingsFile: settingsURL.path,
            weatherFile: weatherURL.path,
            makeID: makeID
        )
        let stateURL = stateFile(paths)
        do {
            let existing = fileSystem.exists(stateURL) ? try fileSystem.read(stateURL) : ""
            try fileSystem.write(try VarStateFile.writing(result.state, into: existing, file: stateURL.path), to: stateURL)
        } catch {
            result.diagnostics.append(Diagnostic(.error, "could not write the imported settings to '\(stateURL.path)'", span: .synthetic(stateURL.path)))
        }
        if result.launcherOnly, let hotkey = result.state["hotkey-launcher"] {
            let launcherURL = launcherOnlyStateFile(paths)
            do {
                let existing = fileSystem.exists(launcherURL) ? try fileSystem.read(launcherURL) : ""
                try fileSystem.write(try VarStateFile.writing(["hotkey-launcher": hotkey], into: existing, file: launcherURL.path), to: launcherURL)
            } catch {
                result.diagnostics.append(Diagnostic(.error, "could not write the imported launcher shortcut to '\(launcherURL.path)'", span: .synthetic(launcherURL.path)))
            }
        }
        let settingsKDL = paths.settingsFile
        do {
            var text = fileSystem.exists(settingsKDL) ? try fileSystem.read(settingsKDL) : ""
            let (current, _) = ShellSettingsFile.parse(text, file: settingsKDL.path)
            if let theme = result.theme, current.theme == nil {
                text = try ShellSettingsFile.updating(text, file: settingsKDL.path, set: .theme(theme))
            }
            if result.launcherOnly, current.config == nil {
                text = try ShellSettingsFile.updating(text, file: settingsKDL.path, set: .config(launcherOnlyConfigID))
            }
            if result.theme != nil || result.launcherOnly {
                try fileSystem.write(text, to: settingsKDL)
            }
        } catch {
            result.diagnostics.append(Diagnostic(.error, "could not write '\(settingsKDL.path)'", span: .synthetic(settingsKDL.path)))
        }
        return result
    }

    public static func convert(
        settings: String?,
        weather: String?,
        launcherOnly: Bool,
        settingsFile: String = "settings.json",
        weatherFile: String = "weather.json",
        makeID: () -> String = { UUID().uuidString }
    ) -> LegacyImportResult {
        var reader = Reader(file: settingsFile)
        var result = LegacyImportResult(launcherOnly: launcherOnly)
        if let settings {
            if let root = reader.object(settings) {
                reader.importSettings(root, into: &result)
            }
        }
        var weatherReader = Reader(file: weatherFile)
        if let weather, let root = weatherReader.object(weather) {
            weatherReader.importWeather(root, into: &result, makeID: makeID)
        }
        result.diagnostics = reader.diagnostics + weatherReader.diagnostics
        return result
    }

    public static func kebab(_ name: String) -> String {
        let characters = Array(name)
        var output = ""
        for (index, character) in characters.enumerated() {
            if character.isUppercase, index > 0 {
                let previous = characters[index - 1]
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                if previous.isLowercase || previous.isNumber || (previous.isUppercase && (next?.isLowercase ?? false)) {
                    output.append("-")
                }
            }
            output.append(contentsOf: character.lowercased())
        }
        return output
    }
}

extension LegacyImport {
    enum OptionType {
        case bool(Bool)
        case text(String, omitEmpty: Bool)
        case choice([String], String)
        case clamped(ClosedRange<Double>, Double)
    }

    struct Option {
        var old: String
        var new: String
        var type: OptionType

        init(_ old: String, _ new: String, _ type: OptionType) {
            self.old = old
            self.new = new
            self.type = type
        }

        init(_ old: String, _ type: OptionType) {
            self.init(old, LegacyImport.kebab(old), type)
        }
    }

    struct Kind {
        var old: String
        var new: String
        var options: [Option]
        var unique: Bool

        init(_ old: String, _ new: String, unique: Bool = false, _ options: [Option] = []) {
            self.old = old
            self.new = new
            self.options = options
            self.unique = unique
        }

        init(_ old: String, unique: Bool = false, _ options: [Option] = []) {
            self.init(old, LegacyImport.kebab(old), unique: unique, options)
        }
    }

    static let sidebarKinds: [Kind] = [
        Kind("dashboardButton"),
        Kind("workspaces", "spaces", [Option("style", .choice(["dots", "numbers"], "dots"))]),
        Kind("dock", unique: true, [Option("showRunning", .bool(true)), Option("iconSize", .choice(["small", "medium", "large"], "medium"))]),
        Kind("clock", [Option("showIcon", .bool(true)), Option("showDate", .bool(false))]),
        Kind("utilitiesButton"),
        Kind("statusIcons", unique: true, [Option("showWifi", "wifi", .bool(true)), Option("showBluetooth", "bluetooth", .bool(true)), Option("showBattery", "battery", .bool(true))]),
        Kind("power"),
        Kind("spacer"),
        Kind("gap", [Option("height", .clamped(4...96, 16))]),
        Kind("divider"),
        Kind("appButton", [Option("bundleID", "bundle-id", .text("", omitEmpty: false))]),
        Kind("battery", [Option("showIcon", .bool(true))]),
        Kind("cpu", [Option("style", .choice(["ring", "percent"], "ring"))]),
        Kind("weather", [Option("showTemperature", .bool(true))]),
        Kind("mediaButton"),
    ]

    static let cardKinds: [Kind] = [
        Kind("weather", [Option("showCondition", .bool(true)), Option("showRange", .bool(true))]),
        Kind("user", [Option("showSystem", .bool(true)), Option("showUptime", .bool(true))]),
        Kind("clock", [Option("style", .choice(["stacked", "inline"], "stacked")), Option("showDate", .bool(false))]),
        Kind("calendar", [Option("firstWeekday", .choice(["monday", "sunday"], "monday")), Option("showWeekNumbers", .bool(false))]),
        Kind("resources", [Option("showCPU", "show-cpu", .bool(true)), Option("showMemory", .bool(true)), Option("showStorage", .bool(true))]),
        Kind("media", [Option("showAlbum", .bool(true)), Option("showSource", .bool(true))]),
    ]

    static let toggleKinds: [Kind] = [
        Kind("wifi", unique: true), Kind("microphone", unique: true), Kind("bluetooth", unique: true),
        Kind("darkMode", unique: true), Kind("nightShift", unique: true), Kind("screenshot", unique: true),
        Kind("showDesktop", unique: true), Kind("colorPicker", unique: true), Kind("lockScreen", unique: true),
        Kind("settings", unique: true), Kind("displaySleep", unique: true),
        Kind("hideApps", unique: true, [Option("keepFrontmost", .bool(false))]),
        Kind("openApp", [Option("bundleID", "bundle-id", .text("", omitEmpty: false)), Option("title", .text("", omitEmpty: true)), Option("symbol", .text("", omitEmpty: true))]),
        Kind("openLink", [Option("url", .text("", omitEmpty: false)), Option("title", .text("", omitEmpty: true)), Option("symbol", .text("", omitEmpty: true))]),
        Kind("runShortcut", [Option("name", .text("", omitEmpty: false)), Option("identifier", .text("", omitEmpty: true)), Option("title", .text("", omitEmpty: true)), Option("symbol", .text("", omitEmpty: true))]),
    ]

    static let tabs = ["dashboard", "media", "performance", "weather"]
    static let utilitiesCards = ["keepAwake", "audio", "quickToggles"]
    static let zones = ["top", "bottom", "side"]
    static let caelestiaZones: [String: [String]] = ["top": ["weather", "user"], "bottom": ["clock", "calendar", "resources"], "side": ["media"]]
    static let zonesByCard: [String: [String]] = [
        "calendar": ["bottom"], "weather": ["top", "bottom", "side"], "user": ["top", "bottom", "side"],
        "clock": ["bottom", "top", "side"], "resources": ["bottom", "top", "side"], "media": ["side", "top", "bottom"],
    ]
    static let rowWidth = 839.0 - 12 - 200

    static func minimumWidth(_ kind: String, in zone: String) -> Double {
        switch (kind, zone) {
        case (_, "side"): 200
        case ("weather", "top"): 275
        case ("user", "top"): 230
        case ("clock", _): 110
        case ("calendar", _): 300
        case ("resources", "bottom"): 90
        case ("resources", _): 230
        case ("media", "top"): 300
        default: 200
        }
    }

    static func fits(_ kinds: [String], in zone: String) -> Bool {
        if zone == "side" { return kinds.count <= 1 }
        let widths = kinds.map { minimumWidth($0, in: zone) }.reduce(0, +)
        return widths + Double(max(kinds.count - 1, 0)) * 12 <= rowWidth
    }

    static let weatherSources = ["openMeteo": "open-meteo", "metNorway": "met-norway", "wttr": "wttr"]
    static let backgrounds = ["material": "material", "glass": "glass", "tintedGlass": "tinted-glass", "fixedGlass": "fixed-glass"]
    static let hotKeyTargets = [("launcher", "hotkey-launcher"), ("dashboard", "hotkey-dashboard"), ("utilities", "hotkey-utilities"), ("nexus", "hotkey-settings")]
    static let freshHotKeys = ["launcher": "alt+space", "dashboard": "ctrl+alt+d", "utilities": "ctrl+alt+u", "nexus": "ctrl+alt+comma"]
    static let modifierNames: [String: HotKeyModifiers] = ["control": .control, "option": .option, "shift": .shift, "command": .command]

    struct Reader {
        var file: String
        var diagnostics: [Diagnostic] = []

        init(file: String) {
            self.file = file
        }

        mutating func report(_ message: String) {
            diagnostics.append(Diagnostic(.warning, "\((file as NSString).lastPathComponent): \(message)", span: .synthetic(file), help: "the default of the setting applies"))
        }

        mutating func object(_ text: String) -> [String: Any]? {
            guard let data = text.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                report("could not be read as JSON, nothing imported")
                return nil
            }
            guard let object = root as? [String: Any] else {
                report("is not a JSON object, nothing imported")
                return nil
            }
            return object
        }

        static func isBool(_ value: Any) -> Bool {
            guard let number = value as? NSNumber else { return false }
            return CFGetTypeID(number) == CFBooleanGetTypeID()
        }

        static func bool(_ value: Any?) -> Bool? {
            guard let value, isBool(value), let number = value as? NSNumber else { return nil }
            return number.boolValue
        }

        static func number(_ value: Any?) -> Double? {
            guard let value, !isBool(value), let number = value as? NSNumber else { return nil }
            return number.doubleValue
        }

        static func string(_ value: Any?) -> String? {
            value as? String
        }

        static func isNull(_ value: Any?) -> Bool {
            value is NSNull
        }

        mutating func section(_ root: [String: Any], _ key: String) -> [String: Any]? {
            guard let value = root[key] else { return nil }
            guard let object = value as? [String: Any] else {
                report("'\(key)' is not an object, skipped")
                return nil
            }
            return object
        }

        mutating func importBool(_ object: [String: Any], _ key: String, path: String, as name: String, into result: inout LegacyImportResult) {
            guard let value = object[key] else { return }
            guard let flag = Self.bool(value) else {
                report("'\(path)' is not true or false, skipped")
                return
            }
            result.state[name] = .bool(flag)
        }

        mutating func importSettings(_ root: [String: Any], into result: inout LegacyImportResult) {
            if let bar = section(root, "bar") {
                importBar(bar, into: &result)
            }
            if let dashboard = section(root, "dashboard") {
                importDashboard(dashboard, into: &result)
            }
            if let utilities = section(root, "utilities"), let layout = section(utilities, "layout") {
                importUtilities(layout, into: &result)
            }
            if let providers = section(root, "providers") {
                importProviders(providers, into: &result)
            }
            if let toasts = section(root, "toasts") {
                importBool(toasts, "chargingChanged", path: "toasts.chargingChanged", as: "toast-charging", into: &result)
                importBool(toasts, "batteryWarnings", path: "toasts.batteryWarnings", as: "toast-battery", into: &result)
                importBool(toasts, "audioOutputChanged", path: "toasts.audioOutputChanged", as: "toast-audio-output", into: &result)
                importBool(toasts, "audioInputChanged", path: "toasts.audioInputChanged", as: "toast-audio-input", into: &result)
            }
            if let background = section(root, "background") {
                importBool(background, "desktopClock", path: "background.desktopClock", as: "desktop-clock", into: &result)
            }
            if let hotKeys = section(root, "hotKeys") {
                importHotKeys(hotKeys, into: &result)
            }
            if let dock = section(root, "appleDockHiding") {
                importBool(dock, "hideWhileRunning", path: "appleDockHiding.hideWhileRunning", as: "hide-apple-dock", into: &result)
            }
            if let keepAwake = section(root, "keepAwake") {
                importBool(keepAwake, "lidClosed", path: "keepAwake.lidClosed", as: "keep-awake-lid", into: &result)
            }
            if let onboarding = section(root, "onboarding") {
                importBool(onboarding, "completed", path: "onboarding.completed", as: "onboarding-done", into: &result)
            }
            if let theme = section(root, "theme"), let raw = theme["name"], !Self.isNull(raw) {
                if let name = Self.string(raw) {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty || trimmed.contains("/") || trimmed.hasPrefix(".") {
                        report("'theme.name' is not a theme name, skipped")
                    } else {
                        result.theme = trimmed
                    }
                } else {
                    report("'theme.name' is not a string, skipped")
                }
            }
        }

        mutating func importBar(_ bar: [String: Any], into result: inout LegacyImportResult) {
            if let raw = bar["layout"] {
                if let list = raw as? [Any] {
                    result.state["sidebar-modules"] = .list(blocks(list, kinds: LegacyImport.sidebarKinds, path: "bar.layout"))
                } else {
                    report("'bar.layout' is not a list, skipped")
                }
            }
            if let raw = bar["screens"] {
                if let screens = raw as? [String: Any], let mode = Self.string(screens["mode"]) {
                    let key = Self.string(screens["screen"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    switch mode {
                    case "all": result.state["sidebar-screens"] = .string("all")
                    case "primary": result.state["sidebar-screens"] = .string("main")
                    case "single" where !key.isEmpty: result.state["sidebar-screens"] = .string(key)
                    default: report("'bar.screens' has no usable screen choice, skipped")
                    }
                } else {
                    report("'bar.screens' has no usable screen choice, skipped")
                }
            }
            if let raw = bar["background"] {
                if let name = Self.string(raw), let mapped = LegacyImport.backgrounds[name] {
                    result.state["sidebar-background"] = .string(mapped)
                } else {
                    report("'bar.background' is not a known background, skipped")
                }
            }
        }

        mutating func record(for entry: [String: Any], kind: Kind, path: String) -> Record {
            var record = Record([("kind", .string(kind.new))])
            let options = entry["options"] as? [String: Any] ?? [:]
            if let raw = entry["options"], !(raw is [String: Any]), !kind.options.isEmpty {
                report("'\(path).options' is not an object, defaults used")
            }
            var values: [(Option, Value)] = []
            for option in kind.options {
                let raw = options[option.old]
                let value: Value?
                switch option.type {
                case .bool(let fallback):
                    let parsed = Self.bool(raw)
                    if raw != nil, parsed == nil { report("'\(path).options.\(option.old)' is not true or false, default used") }
                    value = .bool(parsed ?? fallback)
                case .text(let fallback, let omitEmpty):
                    let parsed = Self.string(raw)
                    if raw != nil, parsed == nil { report("'\(path).options.\(option.old)' is not a string, default used") }
                    let text = parsed ?? fallback
                    value = omitEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .string(text)
                case .choice(let allowed, let fallback):
                    let parsed = Self.string(raw).flatMap { allowed.contains($0) ? $0 : nil }
                    if raw != nil, parsed == nil { report("'\(path).options.\(option.old)' is not one of \(allowed.joined(separator: ", ")), default used") }
                    value = .string(parsed ?? fallback)
                case .clamped(let range, let fallback):
                    let parsed = Self.number(raw).flatMap { $0.isFinite ? $0 : nil }
                    if raw != nil, parsed == nil { report("'\(path).options.\(option.old)' is not a number, default used") }
                    value = .number(min(max(parsed ?? fallback, range.lowerBound), range.upperBound))
                }
                if let value { values.append((option, value)) }
            }
            if kind.old == "resources", !values.contains(where: { $0.1 == .bool(true) }) {
                values = values.map { ($0.0, .bool(true)) }
            }
            for (option, value) in values {
                record[option.new] = value
            }
            return record
        }

        mutating func blocks(_ list: [Any], kinds: [Kind], path: String) -> [Value] {
            var entries: [(id: String, kind: Kind, record: Record)] = []
            var seenUnique: Set<String> = []
            for (index, raw) in list.enumerated() {
                let entryPath = "\(path)[\(index)]"
                guard let entry = raw as? [String: Any] else {
                    report("'\(entryPath)' is not an object, skipped")
                    continue
                }
                guard let name = Self.string(entry["kind"]), let kind = kinds.first(where: { $0.old == name }) else {
                    report("'\(entryPath)' has the unknown kind '\(Self.string(entry["kind"]) ?? "?")', skipped")
                    continue
                }
                if kind.unique, !seenUnique.insert(kind.old).inserted {
                    report("'\(entryPath)' repeats '\(kind.old)', skipped")
                    continue
                }
                let id = Self.string(entry["id"]).map { LegacyImport.renamedID($0, kinds: kinds) } ?? ""
                entries.append((id, kind, record(for: entry, kind: kind, path: entryPath)))
            }
            var taken = Set(entries.map(\.id))
            var used: Set<String> = []
            var values: [Value] = []
            for var entry in entries {
                if entry.id.isEmpty || used.contains(entry.id) {
                    entry.id = LegacyImport.uniqueID(for: entry.kind.new, taken: taken)
                    taken.insert(entry.id)
                }
                used.insert(entry.id)
                var record = Record([("id", .string(entry.id))])
                for key in entry.record.keys { record[key] = entry.record[key] }
                values.append(.record(record))
            }
            return values
        }

        mutating func importDashboard(_ dashboard: [String: Any], into result: inout LegacyImportResult) {
            if let raw = dashboard["tabs"] {
                if let list = raw as? [Any] {
                    var order: [String] = []
                    var hidden: Set<String> = []
                    for (index, item) in list.enumerated() {
                        guard let object = item as? [String: Any], let id = Self.string(object["id"]), LegacyImport.tabs.contains(id) else {
                            report("'dashboard.tabs[\(index)]' is not a known tab, skipped")
                            continue
                        }
                        if order.contains(id) { continue }
                        order.append(id)
                        let visible = object["visible"]
                        if visible != nil, Self.bool(visible) == nil { report("'dashboard.tabs[\(index)].visible' is not true or false, default used") }
                        if Self.bool(visible) == false { hidden.insert(id) }
                    }
                    order += LegacyImport.tabs.filter { !order.contains($0) }
                    if order.allSatisfy({ hidden.contains($0) }), let first = order.first { hidden.remove(first) }
                    result.state["dashboard-tabs"] = .list(order.map { .record(Record([("id", .string($0)), ("visible", .bool(!hidden.contains($0)))])) })
                } else {
                    report("'dashboard.tabs' is not a list, skipped")
                }
            }
            if let raw = dashboard["cards"] {
                guard let cards = raw as? [String: Any] else {
                    report("'dashboard.cards' is not an object, skipped")
                    return
                }
                var zones: [String: [(String, Record)]] = [:]
                for zone in LegacyImport.zones {
                    if let list = cards[zone] as? [Any] {
                        var items: [(String, Record)] = []
                        for (index, item) in list.enumerated() {
                            let itemPath = "dashboard.cards.\(zone)[\(index)]"
                            guard let object = item as? [String: Any] else {
                                report("'\(itemPath)' is not an object, skipped")
                                continue
                            }
                            guard let name = Self.string(object["kind"]), let kind = LegacyImport.cardKinds.first(where: { $0.old == name }) else {
                                report("'\(itemPath)' has the unknown card '\(Self.string(object["kind"]) ?? "?")', skipped")
                                continue
                            }
                            items.append((kind.new, record(for: object, kind: kind, path: itemPath)))
                        }
                        zones[zone] = items
                    } else {
                        if cards[zone] != nil { report("'dashboard.cards.\(zone)' is not a list, default used") }
                        zones[zone] = (LegacyImport.caelestiaZones[zone] ?? []).compactMap { name in
                            LegacyImport.cardKinds.first { $0.old == name }.map { kind in (kind.new, record(for: [:], kind: kind, path: "")) }
                        }
                    }
                }
                var seen: Set<String> = []
                for zone in LegacyImport.zones {
                    var kept: [(String, Record)] = []
                    for (kind, record) in zones[zone] ?? [] {
                        guard !seen.contains(kind), LegacyImport.zonesByCard[kind]?.contains(zone) == true else {
                            report("card '\(kind)' does not fit 'dashboard.cards.\(zone)', skipped")
                            continue
                        }
                        guard LegacyImport.fits(kept.map(\.0) + [kind], in: zone) else {
                            report("card '\(kind)' does not fit 'dashboard.cards.\(zone)', skipped")
                            continue
                        }
                        seen.insert(kind)
                        kept.append((kind, record))
                    }
                    result.state["dashboard-cards-\(zone)"] = .list(kept.map { kind, record in
                        var full = Record([("id", .string(kind))])
                        for key in record.keys { full[key] = record[key] }
                        return .record(full)
                    })
                }
            }
        }

        mutating func importUtilities(_ layout: [String: Any], into result: inout LegacyImportResult) {
            if let raw = layout["cards"] {
                if let list = raw as? [Any] {
                    var cards: [(String, Bool)] = []
                    for (index, item) in list.enumerated() {
                        guard let object = item as? [String: Any], let kind = Self.string(object["kind"]), LegacyImport.utilitiesCards.contains(kind) else {
                            report("'utilities.layout.cards[\(index)]' is not a known card, skipped")
                            continue
                        }
                        if cards.contains(where: { $0.0 == kind }) { continue }
                        let enabled = object["enabled"]
                        if enabled != nil, Self.bool(enabled) == nil { report("'utilities.layout.cards[\(index)].enabled' is not true or false, default used") }
                        cards.append((kind, Self.bool(enabled) ?? true))
                    }
                    for kind in LegacyImport.utilitiesCards where !cards.contains(where: { $0.0 == kind }) {
                        cards.append((kind, true))
                    }
                    result.state["utilities-cards"] = .list(cards.map { .record(Record([("kind", .string(LegacyImport.kebab($0.0))), ("enabled", .bool($0.1))])) })
                } else {
                    report("'utilities.layout.cards' is not a list, skipped")
                }
            }
            if let raw = layout["quickToggles"] {
                if let list = raw as? [Any] {
                    result.state["utilities-toggles"] = .list(blocks(list, kinds: LegacyImport.toggleKinds, path: "utilities.layout.quickToggles"))
                } else {
                    report("'utilities.layout.quickToggles' is not a list, skipped")
                }
            }
        }

        mutating func importProviders(_ providers: [String: Any], into result: inout LegacyImportResult) {
            if let raw = providers["weather"] {
                if let name = Self.string(raw), let mapped = LegacyImport.weatherSources[name] {
                    result.state["weather-source"] = .string(mapped)
                } else {
                    report("'providers.weather' is not a known weather source, skipped")
                }
            }
            if let raw = providers["fileManager"], !Self.isNull(raw) {
                if let id = Self.string(raw) {
                    let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { result.state["file-manager"] = .string(trimmed) }
                } else {
                    report("'providers.fileManager' is not a string, skipped")
                }
            }
        }

        mutating func importHotKeys(_ hotKeys: [String: Any], into result: inout LegacyImportResult) {
            for (key, name) in LegacyImport.hotKeyTargets {
                guard let raw = hotKeys[key] else {
                    result.state[name] = .string(LegacyImport.freshHotKeys[key] ?? "")
                    continue
                }
                if Self.isNull(raw) {
                    result.state[name] = .string("")
                    continue
                }
                guard let object = raw as? [String: Any], let code = Self.number(object["keyCode"]), code == code.rounded(), (0..<128).contains(code) else {
                    report("'hotKeys.\(key)' is not a shortcut, skipped")
                    continue
                }
                var modifiers: HotKeyModifiers = []
                if let names = object["modifiers"] as? [Any] {
                    for item in names {
                        if let text = Self.string(item), let flag = LegacyImport.modifierNames[text.lowercased()] { modifiers.insert(flag) }
                    }
                }
                guard let chord = LegacyImport.chord(keyCode: UInt32(code), modifiers: modifiers) else {
                    report("'hotKeys.\(key)' uses key code \(Int(code)), which 0.2 cannot bind, skipped")
                    continue
                }
                result.state[name] = .string(chord)
            }
        }

        mutating func importWeather(_ root: [String: Any], into result: inout LegacyImportResult, makeID: () -> String) {
            var places: [Record] = []
            if let raw = root["favorites"] {
                guard let list = raw as? [Any] else {
                    report("'favorites' is not a list, skipped")
                    return
                }
                for (index, item) in list.enumerated() {
                    guard let object = item as? [String: Any],
                          let latitude = Self.number(object["latitude"]), let longitude = Self.number(object["longitude"]),
                          (-90...90).contains(latitude), (-180...180).contains(longitude) else {
                        report("'favorites[\(index)]' is not a place on earth, skipped")
                        continue
                    }
                    let id: String
                    if let raw = object["id"], !Self.isNull(raw) {
                        guard let text = Self.string(raw), UUID(uuidString: text) != nil else {
                            report("'favorites[\(index)].id' is not an id, skipped")
                            continue
                        }
                        id = text
                    } else {
                        id = makeID()
                    }
                    places.append(Self.place(id: id, name: Self.string(object["name"]), latitude: latitude, longitude: longitude))
                }
            } else if let latitude = Self.number(root["latitude"]), let longitude = Self.number(root["longitude"]),
                      (-90...90).contains(latitude), (-180...180).contains(longitude) {
                places.append(Self.place(id: makeID(), name: Self.string(root["name"]), latitude: latitude, longitude: longitude))
            } else {
                return
            }
            result.state["weather-places"] = .list(places.map(Value.record))
            let ids = places.compactMap { record -> String? in
                if case .string(let id)? = record["id"] { return id }
                return nil
            }
            if let raw = root["selectedID"], !Self.isNull(raw) {
                if let id = Self.string(raw), ids.contains(id) {
                    result.state["weather-selected"] = .string(id)
                    return
                }
                report("'selectedID' is not one of the favorites, the first one is used")
            }
            if let first = ids.first {
                result.state["weather-selected"] = .string(first)
            }
        }

        static func place(id: String, name: String?, latitude: Double, longitude: Double) -> Record {
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Record([
                ("id", .string(id)),
                ("name", .string(trimmed.isEmpty ? "Location" : trimmed)),
                ("latitude", .number(latitude)),
                ("longitude", .number(longitude)),
            ])
        }
    }

    static func renamedID(_ id: String, kinds: [Kind]) -> String {
        for kind in kinds {
            if id == kind.old { return kind.new }
            if id.hasPrefix(kind.old + "-"), Int(id.dropFirst(kind.old.count + 1)) != nil {
                return kind.new + id.dropFirst(kind.old.count)
            }
        }
        return kebab(id)
    }

    static func uniqueID(for kind: String, taken: Set<String>) -> String {
        if !taken.contains(kind) { return kind }
        var n = 2
        while taken.contains("\(kind)-\(n)") { n += 1 }
        return "\(kind)-\(n)"
    }

    static func chord(keyCode: UInt32, modifiers: HotKeyModifiers) -> String? {
        guard let key = KeyChord.keyCodes.filter({ $0.value == keyCode }).map(\.key).sorted().first else { return nil }
        return KeyChord(modifiers: modifiers, key: key, keyCode: keyCode).canonical
    }
}
