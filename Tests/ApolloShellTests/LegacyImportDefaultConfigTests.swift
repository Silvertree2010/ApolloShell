import Foundation
import Testing
import ApolloBase
import ApolloKDL
import ApolloConfig

@Suite("Übernahme 0.1.4.2 gegen die Default-Config")
struct LegacyImportDefaultConfigTests {
    static let fixtures = PackageResources.root.appendingPathComponent("Tests/Fixtures/legacy-0.1.4.2")
    static let presets = PackageResources.configs.appendingPathComponent("apolloshell-default/presets.kdl")

    static func convert(_ settings: String, _ weather: String?) throws -> LegacyImportResult {
        LegacyImport.convert(
            settings: try String(contentsOf: fixtures.appendingPathComponent(settings), encoding: .utf8),
            weather: try weather.map { try String(contentsOf: fixtures.appendingPathComponent($0), encoding: .utf8) },
            launcherOnly: false,
            makeID: { "00000000-0000-0000-0000-000000000001" }
        )
    }

    static func presetValues() throws -> [String: Value] {
        let document = try KDLDocument.parse(try String(contentsOf: presets, encoding: .utf8), file: presets.path)
        var values: [String: Value] = [:]
        for node in document.nodes where node.name == "let" {
            guard case .string(let name)? = node.arguments.first?.scalar else { continue }
            let body = KDLNode(name: name, children: node.children)
            values[name] = ValueKDLMapping.value(from: body)
        }
        return values
    }

    @Test("übernommene Werte passen zu den gespeicherten var der Default-Config, ohne Diagnose", arguments: [
        ("settings-full.json", "weather.json"),
        ("settings-broken.json", "weather-broken.json"),
        ("settings-first-launch.json", "weather-single.json"),
    ])
    func stateLoadsAgainstDeclarations(settings: String, weather: String) throws {
        let ir = try #require(PackageResources.load(DefaultConfigTests.defaultFolder, id: "apolloshell-default").ir)
        let result = try Self.convert(settings, weather)
        let text = try VarStateFile.writing(result.state, into: "", file: "state.kdl")
        let (values, diagnostics) = VarStateFile.read(text, file: "state.kdl", declarations: ir.vars)
        #expect(diagnostics.isEmpty, "\(diagnostics.map(\.message))")
        #expect(values == result.state)
        let persisted = Set(ir.vars.filter(\.persist).map(\.name))
        #expect(Set(result.state.keys).isSubset(of: persisted))
    }

    @Test("settings.json einer frischen 0.1.4.2 ergibt genau die Vorlagen der Default-Config")
    func firstLaunchMatchesPresets() throws {
        let presets = try Self.presetValues()
        let state = try Self.convert("settings-first-launch.json", nil).state
        func field(_ preset: String, _ key: String) -> Value? {
            guard case .record(let record)? = presets[preset] else { return nil }
            return record[key]
        }
        #expect(state["sidebar-modules"] == presets["sidebar-caelestia"])
        #expect(state["dashboard-tabs"] == presets["dashboard-tabs-all"])
        #expect(state["dashboard-cards-top"] == field("dashboard-caelestia", "top"))
        #expect(state["dashboard-cards-bottom"] == field("dashboard-caelestia", "bottom"))
        #expect(state["dashboard-cards-side"] == field("dashboard-caelestia", "side"))
        #expect(state["utilities-cards"] == field("utilities-standard", "cards"))
        #expect(state["utilities-toggles"] == field("utilities-standard", "toggles"))
        #expect(state["hotkey-launcher"] == field("hotkeys-default", "launcher"))
        #expect(state["hotkey-dashboard"] == field("hotkeys-default", "dashboard"))
        #expect(state["hotkey-utilities"] == field("hotkeys-default", "utilities"))
        #expect(state["hotkey-settings"] == field("hotkeys-default", "settings"))
        #expect(state["sidebar-screens"] == .string("all"))
        #expect(state["sidebar-background"] == .string("material"))
        #expect(state["weather-source"] == .string("open-meteo"))
        #expect(state["file-manager"] == nil)
    }
}
