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
        for node in document.nodes where node.name == "var" {
            guard case .string(let name)? = node.arguments.first?.scalar else { continue }
            if node.children == nil, node.arguments.count > 1 {
                switch node.arguments[1].scalar {
                case .string(let text): values[name] = .string(text)
                case .bool(let flag): values[name] = .bool(flag)
                case .number(let number, _): values[name] = .number(number)
                default: values[name] = .null
                }
                continue
            }
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
        let persisted = Set(ir.vars.filter(\.persist).map(\.name))
        let shared = result.state.filter { persisted.contains($0.key) }
        #expect(!shared.isEmpty)
        #expect(values.filter { persisted.contains($0.key) } == shared)
        #expect(diagnostics.allSatisfy { message in !shared.keys.contains { message.message.contains("'\($0)'") } }, "\(diagnostics.map(\.message))")
    }

    @Test("settings.json einer frischen 0.1.4.2 ergibt genau die Vorlagen der Default-Config")
    func firstLaunchMatchesPresets() throws {
        let presets = try Self.presetValues()
        let state = try Self.convert("settings-first-launch.json", nil).state
        for name in ["hotkey-launcher", "hotkey-dashboard", "hotkey-utilities", "hotkey-settings", "onboarding-done", "desktop-clock"] {
            guard let value = state[name] else { continue }
            #expect(value == presets[name], "\(name) \(value)")
        }
        #expect(state["file-manager"] == nil)
    }
}
