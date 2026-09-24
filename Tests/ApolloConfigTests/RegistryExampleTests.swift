import Testing
import Foundation
import ApolloBase
import ApolloConfig

struct RegistryExample: Sendable, CustomTestStringConvertible {
    var name: String
    var context: NodeContext
    var example: String

    var testDescription: String { "\(name) (\(context.rawValue))" }

    static let preferredContexts: [NodeContext] = [.surfaceBody, .topLevel, .elementBody, .actions, .menu, .commandCenterItems, .wmBlock, .settingsFile, .stateFile]

    static var all: [RegistryExample] {
        let registry = SchemaRegistry.builtin
        let schemas = Array(registry.nodes.values) + Array(registry.menuSources.values)
        return schemas
            .map { schema in
                let context = preferredContexts.first { schema.contexts.contains($0) } ?? .topLevel
                return RegistryExample(name: schema.name, context: context, example: schema.example)
            }
            .sorted { ($0.name, $0.context.rawValue, $0.example) < ($1.name, $1.context.rawValue, $1.example) }
    }

    static let placeholder = "@@"

    static let preludes: [String: String] = [
        "use": "define \"labeled-icon\" {\n    param \"icon\"\n    icon \"{icon}\"\n}\n",
        "disable": "bind \"alt+space\" {\n    toggle \"launcher\"\n}\n",
        "switch": "var tab \"a\"\n",
        "toggle": "var dark-mode #false\n",
        "input": "var launcher-query \"\"\n",
        "key-recorder": "var launcher-key \"alt+space\"\n",
        "reorderable": "var items type=\"list\"\n",
        "accessibility-action": "var items type=\"list\"\n",
        "flyout": "var popout-open #false\n",
    ]

    static let templates: [String: String] = [
        "else": "panel \"example\" {\nwhen \"{battery.present}\" {\n    text \"on battery\"\n}\n@@\n}\n",
        "case": "var tab \"a\"\npanel \"example\" {\nswitch \"{var.tab}\" {\n@@\n}\n}\n",
        "default": "var tab \"a\"\npanel \"example\" {\nswitch \"{var.tab}\" {\ncase \"a\" {\n    text \"A\"\n}\n@@\n}\n}\n",
        "param": "define \"example\" {\n@@\nicon \"{icon}\"\n}\n",
        "slot": "define \"example\" {\ncolumn {\n@@\n}\n}\n",
        "fill": "define \"card\" {\n    column {\n        slot \"header\"\n    }\n}\npanel \"example\" {\nuse \"card\" {\n@@\n}\n}\n",
    ]

    static let contextTemplates: [NodeContext: String] = [
        .topLevel: "@@\n",
        .surfaceBody: "panel \"example\" {\n@@\n}\n",
        .elementBody: "panel \"example\" {\nbutton {\n@@\n}\n}\n",
        .actions: "bind \"alt+e\" {\n@@\n}\n",
        .menu: "panel \"example\" {\ntext \"x\" {\nmenu {\n@@\n}\n}\n}\n",
        .commandCenterItems: "command-center {\n@@\n}\n",
        .wmBlock: "wm {\n@@\n}\n",
    ]

    static let extraFiles: [String: [String: String]] = [
        "include": ["/config/sidebar-modules.kdl": "text \"module\"\n"],
        "style": ["/config/theme.css": ""],
    ]

    var bindings: (before: String, after: String) {
        switch name {
        case "app-icon", "app-dock", "app-commands", "app-windows", "source":
            return ("each app in=\"{apps.running}\" {\n", "\n}")
        case "theme-preview":
            return ("each item in=\"{marketplace.items}\" {\n", "\n}")
        default:
            return ("", "")
        }
    }

    func files() -> [String: String] {
        let template = Self.templates[name] ?? Self.contextTemplates[context] ?? "@@\n"
        let bound = bindings.before + example + bindings.after
        var files = Self.extraFiles[name] ?? [:]
        files["/config/shell.kdl"] = (Self.preludes[name] ?? "") + template.replacingOccurrences(of: Self.placeholder, with: bound)
        return files
    }
}

@Suite("Beispiele der Registry")
struct RegistryExampleTests {
    @Test("jede Beschreibung hat ein Beispiel")
    func everySchemaHasAnExample() {
        let missing = RegistryExample.all.filter { $0.example.isEmpty }.map(\.name)
        #expect(missing.isEmpty, "\(missing)")
    }

    @Test("jedes Beispiel der Registry laedt ohne Diagnose", arguments: RegistryExample.all)
    func exampleLoadsWithoutDiagnostics(_ example: RegistryExample) {
        if example.context == .settingsFile {
            let (_, diagnostics) = ShellSettingsFile.parse(example.example, file: "/config/settings.kdl")
            #expect(diagnostics.isEmpty, "\(diagnostics.map(\.message))")
            return
        }
        let files = example.files()
        let result = LoaderHarness.load(files)
        #expect(result.diagnostics.isEmpty, "\(files["/config/shell.kdl"] ?? "")\n\(result.diagnostics.map { "\($0.span.map { "\($0.start.line):\($0.start.column)" } ?? "-") \($0.message)" })")
        #expect(result.ir != nil)
    }
}
