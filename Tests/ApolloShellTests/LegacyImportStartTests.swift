import Testing
import Foundation
import ApolloBase
import ApolloConfig
@testable import ApolloShell

@MainActor
@Suite("Start: einmalige Übernahme der 0.1.4.2-Einstellungen (runtime.md 12)", .serialized)
struct LegacyImportStartTests {
    static let fixtures = PackageResources.root.appendingPathComponent("Tests/Fixtures/legacy-0.1.4.2")

    struct Home {
        let root: URL
        var support: URL { root.appendingPathComponent("Library/Application Support/ApolloShell") }
        var settingsJSON: URL { support.appendingPathComponent("settings.json") }
        var weatherJSON: URL { support.appendingPathComponent("weather.json") }
        var config: URL { root.appendingPathComponent("apolloshell") }
        var settingsKDL: URL { config.appendingPathComponent("settings.kdl") }
        var state: URL { config.appendingPathComponent("state") }
        var defaultState: URL { state.appendingPathComponent("apolloshell-default.kdl") }
        var launcherState: URL { state.appendingPathComponent("launcher-only.kdl") }
    }

    static func fixture(_ name: String) throws -> String {
        try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
    }

    static func home(settings: String, weather: String? = "weather.json") throws -> Home {
        let home = Home(root: FileManager.default.temporaryDirectory.appendingPathComponent("legacy-start-\(UUID().uuidString)"))
        try FileManager.default.createDirectory(at: home.support, withIntermediateDirectories: true)
        try Data(try fixture(settings).utf8).write(to: home.settingsJSON)
        if let weather { try Data(try fixture(weather).utf8).write(to: home.weatherJSON) }
        return home
    }

    static func shell(_ home: Home, defaults: [String: Any] = [:]) throws -> LiveShell {
        let options = LiveShell.Options(config: nil, resources: PackageResources.root.appendingPathComponent("Resources"),
                                        fixture: PackageResources.root.appendingPathComponent("Resources/render/fixture.kdl"))
        let shell = LiveShell(options: options, host: WindowHost(factory: FakeFactory()), environment: ["XDG_CONFIG_HOME": home.root.path], home: home.root)
        let real = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        for path in [shell.paths.applicationSupport.path, shell.paths.userConfig.path, shell.paths.stateDirectory.path, shell.settings.file.path] {
            try #require(path.hasPrefix(home.root.path + "/"), "\(path) is outside the test folder")
            try #require(!path.hasPrefix(real + "/Library/Application Support/ApolloShell"))
            try #require(!path.hasPrefix(real + "/.config/apolloshell"))
        }
        shell.interactive = false
        shell.registrar = FakeRegistrar()
        shell.legacyDefaults = { defaults[$0] }
        return shell
    }

    static func state(_ file: URL) throws -> [String: Value] {
        VarStateFile.readAll(try String(contentsOf: file, encoding: .utf8), file: file.path).0
    }

    @Test("erster Start: Werte landen in state/apolloshell-default.kdl, das Theme in settings.kdl")
    func firstStartImports() async throws {
        let home = try Self.home(settings: "settings-full.json")
        let shell = try Self.shell(home)
        try await shell.start()
        defer { shell.shutdown() }
        let expected = LegacyImport.convert(settings: try Self.fixture("settings-full.json"), weather: nil, launcherOnly: false).state
        #expect(!expected.isEmpty)
        let stored = try Self.state(home.defaultState)
        for (key, value) in expected { #expect(stored[key] == value, "\(key)") }
        #expect(stored.count > expected.count)
        #expect(stored["file-manager"] == .string("com.binarynights.ForkLift"))
        let settingsText = try String(contentsOf: home.settingsKDL, encoding: .utf8)
        #expect(ShellSettingsFile.parse(settingsText, file: home.settingsKDL.path).0.theme == "Catppuccin Mocha")
        #expect(!FileManager.default.fileExists(atPath: home.launcherState.path))
    }

    @Test("zweiter Start: nichts wird erneut übernommen")
    func secondStartKeepsState() async throws {
        let home = try Self.home(settings: "settings-full.json")
        let first = try Self.shell(home)
        try await first.start()
        first.shutdown()
        let changed = try Self.fixture("settings-full.json")
            .replacingOccurrences(of: "com.binarynights.ForkLift", with: "com.apple.finder")
            .replacingOccurrences(of: "Catppuccin Mocha", with: "Nord")
        try Data(changed.utf8).write(to: home.settingsJSON)
        let stateBefore = try Data(contentsOf: home.defaultState)
        let settingsBefore = try Data(contentsOf: home.settingsKDL)
        let second = try Self.shell(home, defaults: ["launcherOnly": true])
        try await second.start()
        defer { second.shutdown() }
        #expect(try Data(contentsOf: home.defaultState) == stateBefore)
        #expect(try Data(contentsOf: home.settingsKDL) == settingsBefore)
        #expect(!FileManager.default.fileExists(atPath: home.launcherState.path))
        #expect(second.location?.id == "apolloshell-default")
    }

    @Test("Nur-Launcher: config \"launcher-only\" aktiv und das Launcher-Kürzel übernommen")
    func launcherOnly() async throws {
        let home = try Self.home(settings: "settings-full.json")
        let shell = try Self.shell(home, defaults: ["launcherOnly": true])
        try await shell.start()
        defer { shell.shutdown() }
        let expected = LegacyImport.convert(settings: try Self.fixture("settings-full.json"), weather: nil, launcherOnly: true).state["hotkey-launcher"]
        #expect(expected != nil)
        #expect(try Self.state(home.launcherState)["hotkey-launcher"] == expected)
        let settingsText = try String(contentsOf: home.settingsKDL, encoding: .utf8)
        #expect(ShellSettingsFile.parse(settingsText, file: home.settingsKDL.path).0.config == "launcher-only")
        #expect(shell.location?.id == "launcher-only")
    }

    @Test("die alten Dateien sind danach byte-gleich")
    func oldFilesUntouched() async throws {
        let home = try Self.home(settings: "settings-full.json")
        let settingsBefore = try Data(contentsOf: home.settingsJSON)
        let weatherBefore = try Data(contentsOf: home.weatherJSON)
        let shell = try Self.shell(home, defaults: ["nurLauncher": true])
        try await shell.start()
        shell.shutdown()
        #expect(try Data(contentsOf: home.settingsJSON) == settingsBefore)
        #expect(try Data(contentsOf: home.weatherJSON) == weatherBefore)
        #expect(FileManager.default.fileExists(atPath: home.defaultState.path))
    }

    @Test("nach dem Import ist die übernommene Config aktiv, der SettingsStore hat neu gelesen")
    func activeConfigAfterImport() async throws {
        let home = try Self.home(settings: "settings-full.json")
        let shell = try Self.shell(home, defaults: ["launcherOnly": true])
        #expect(shell.settings.settings.config == nil)
        #expect(shell.activeLocation().id == "apolloshell-default")
        try await shell.start()
        defer { shell.shutdown() }
        #expect(shell.settings.settings.config == "launcher-only")
        #expect(shell.settings.settings.theme == "Catppuccin Mocha")
        #expect(shell.location?.id == "launcher-only")
        let hotkey = try Self.state(home.launcherState)["hotkey-launcher"]
        #expect(shell.assembly?.vars.value("hotkey-launcher") == hotkey)
    }

    @Test("Standard-Config übernimmt die Werte in die laufenden var")
    func defaultConfigUsesImportedValues() async throws {
        let home = try Self.home(settings: "settings-full.json")
        let shell = try Self.shell(home)
        try await shell.start()
        defer { shell.shutdown() }
        #expect(shell.location?.id == "apolloshell-default")
        #expect(shell.assembly?.vars.value("file-manager") == .string("com.binarynights.ForkLift"))
    }

    @Test("kaputtes settings.json verhindert den Start nicht, Übersprungenes steht unter Show Problems", arguments: [
        "settings-truncated.json", "settings-broken.json",
    ])
    func brokenSettings(_ name: String) async throws {
        let home = try Self.home(settings: name, weather: "weather-broken.json")
        let shell = try Self.shell(home)
        try await shell.start()
        defer { shell.shutdown() }
        #expect(shell.steps.last == "started")
        #expect(shell.location?.id == "apolloshell-default")
        let expected = LegacyImport.convert(settings: try Self.fixture(name), weather: try Self.fixture("weather-broken.json"), launcherOnly: false).diagnostics
        #expect(!expected.isEmpty)
        func listed() -> Bool {
            expected.allSatisfy { wanted in
                shell.overlay.problems.contains { $0.message == wanted.message && $0.severity == wanted.severity }
            }
        }
        #expect(listed(), "\(shell.overlay.problems.map(\.message))")
        #expect(shell.overlay.problems.contains { $0.span?.file == home.settingsJSON.path })
        await shell.reload()?.value
        #expect(listed())
        #expect(FileManager.default.fileExists(atPath: home.state.path))
    }
}
