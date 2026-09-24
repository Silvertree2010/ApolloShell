import Testing
import Foundation
import ApolloBase
import ApolloConfig
import ApolloKDL
import ApolloWMCore
@testable import ApolloProviders

@MainActor
@Suite("wm-Beispieldateien")
struct WMExampleFilesTests {
    static let examples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/configs/apolloshell-default/examples")

    static func text(_ name: String) throws -> String {
        try String(contentsOf: examples.appendingPathComponent(name), encoding: .utf8)
    }

    static func load(_ shell: String) throws -> (ConfigIR?, [Diagnostic]) {
        let files = [
            "/config/shell.kdl": shell,
            "/builtin/apolloshell-default/examples/tiling-keys.kdl": try text("tiling-keys.kdl"),
            "/builtin/apolloshell-default/examples/tiling-tabs.kdl": try text("tiling-tabs.kdl"),
        ]
        let paths = ConfigPaths(builtinConfigs: URL(fileURLWithPath: "/builtin"), userConfig: URL(fileURLWithPath: "/config"), applicationSupport: URL(fileURLWithPath: "/support"))
        let loader = ConfigLoader(fileSystem: MemoryFileSystem(files), paths: paths, registry: .builtin, filters: .builtin, shellVersion: "0.2.0")
        let result = loader.load(ConfigLocation(id: "mine", root: URL(fileURLWithPath: "/config"), isBuiltin: false))
        return (result.ir, result.diagnostics)
    }

    @Test("Beide Dateien laden per builtin:-include ohne Fehler")
    func loads() throws {
        let (ir, diagnostics) = try Self.load("""
        wm enabled=#true
        include "builtin:apolloshell-default/examples/tiling-keys.kdl"
        include "builtin:apolloshell-default/examples/tiling-tabs.kdl"
        """)
        #expect(diagnostics.filter { $0.severity != .note }.isEmpty, "\(diagnostics.map(\.message))")
        #expect(ir?.binds.count == Command.defaultBindings.count)
        #expect(ir?.surface("wm-tab-bars")?.kind == "overlay")
    }

    @Test("tiling-keys enthält jede Vorgabe-Taste genau einmal mit ihrem Befehl")
    func coversDefaults() throws {
        let document = try KDLDocument.parse(try Self.text("tiling-keys.kdl"), file: "tiling-keys.kdl")
        var found: [UInt16: Command] = [:]
        for node in document.nodes {
            #expect(node.name == "bind")
            guard case .string(let chord) = node.arguments.first?.scalar, chord.hasPrefix("hyper+"),
                  let code = KeyNames.code(String(chord.dropFirst(6))),
                  let action = node.children?.first else {
                Issue.record("unlesbar: \(node.name)")
                continue
            }
            let values: [Value] = action.arguments.map { argument in
                switch argument.scalar {
                case .string(let text): .string(text)
                case .number(let number, _): .number(number)
                default: .null
                }
            }
            #expect(found[code] == nil)
            found[code] = try WMProvider.command(ActionArguments(action.name, values))
        }
        #expect(found == Command.defaultBindings)
    }
}
