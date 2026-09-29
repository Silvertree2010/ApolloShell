import Testing
import Foundation
import ApolloBase
import ApolloConfig
@testable import ApolloControl

@Suite("Referenz-Doku und veröffentlichtes Schema (testing.md 2.5)")
struct SchemaDocsTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func markdown() throws -> String {
        try #require(SchemaText.render(.builtin, name: nil, format: .markdown)?.first)
    }

    @Test("docs/CONFIG.md entspricht apollo schema --markdown")
    func configDocMatches() throws {
        let file = try String(contentsOf: Self.root.appendingPathComponent("docs/CONFIG.md"), encoding: .utf8)
        #expect(file == (try Self.markdown()) + "\n", "run: apollo schema --markdown > docs/CONFIG.md")
    }

    @Test("Markdown: Abschnitte je Art, Tabellenzellen ohne rohes |, Stufe und Vorgaben sichtbar")
    func markdownShape() throws {
        let text = try Self.markdown()
        #expect(text.hasPrefix("# Configuration reference"))
        let headings = text.split(separator: "\n").filter { $0.hasPrefix("## ") }.map(String.init)
        #expect(headings == ["## Nodes", "## Actions", "## Providers", "## Filters", "## Events"])
        let registry = SchemaRegistry.builtin
        #expect(text.components(separatedBy: "\n### `").count - 1 == SchemaText.entries(registry).count)
        for line in text.split(separator: "\n") where line.hasPrefix("| ") && !line.hasPrefix("| ---") {
            let unescaped = line.replacingOccurrences(of: "\\|", with: "")
            #expect(unescaped.filter { $0 == "|" }.count == 6, "\(line)")
        }
        let entry = SchemaEntry(kind: "node", name: "x", doc: "d", example: nil, arguments: [],
                                properties: [PropertySchema(name: "mode", type: .enumeration(["a", "b"]), defaultValue: .string("a"), doc: "m")],
                                fields: [], members: ["on-click"], stability: "experimental")
        let single = SchemaText.markdown(entry)
        #expect(single.hasPrefix("### `x` (node, *experimental*)"))
        #expect(single.contains("| property | `mode` | \"a\"\\|\"b\" | `\"a\"` | m |"))
        #expect(single.contains("Handlers: `on-click`"))
    }

    @Test("JSON nennt Stufe und Feature je Eintrag")
    func jsonCarriesStability() throws {
        let text = try #require(SchemaText.render(.builtin, name: nil, format: .json)?.first)
        guard case .list(let entries)? = JSONText.decode(text) else { Issue.record("no list"); return }
        #expect(!entries.isEmpty)
        for case .record(let entry) in entries {
            guard case .string(let stability)? = entry["stability"] else { Issue.record("no stability"); continue }
            #expect(["stable", "experimental"].contains(stability))
            #expect(entry["feature"] != nil)
        }
    }

    @Test("Jeder stable-Name aus schema/<version>.json bleibt mit gleichem Typ")
    func publishedNamesStay() throws {
        let folder = Self.root.appendingPathComponent("schema")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        #expect(!files.isEmpty)
        let current = Dictionary(SchemaText.entries(.builtin).map { ("\($0.kind) \($0.name)", $0) }, uniquingKeysWith: { first, _ in first })
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard case .list(let entries)? = JSONText.decode(text) else { Issue.record("\(file.lastPathComponent) is not a list"); continue }
            for case .record(let old) in entries where old["stability"] == .string("stable") {
                guard case .string(let kind)? = old["kind"], case .string(let name)? = old["name"] else { continue }
                guard let now = current["\(kind) \(name)"] else {
                    Issue.record("\(file.lastPathComponent): \(kind) '\(name)' is gone")
                    continue
                }
                Self.compare(old["arguments"], now.arguments.map { ($0.name, SchemaText.typeText($0.type)) }, key: "name", label: "\(name) argument", file: file)
                Self.compare(old["properties"], now.properties.map { ($0.name, SchemaText.typeText($0.type)) }, key: "name", label: "\(name) property", file: file, stableOnly: true)
                Self.compare(old["fields"], now.fields.map { ($0.path.joined(separator: "."), SchemaText.typeText($0.type)) }, key: "path", label: "\(name) field", file: file)
            }
        }
    }

    static func grows(_ old: String, into new: String?) -> Bool {
        guard let new, old.hasPrefix("\""), new.hasPrefix("\"") else { return false }
        func values(_ text: String) -> Set<String> {
            Set(text.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) })
        }
        return values(old).isSubset(of: values(new))
    }

    static func compare(_ old: Value?, _ now: [(String, String)], key: String, label: String, file: URL, stableOnly: Bool = false) {
        guard case .list(let items)? = old else { return }
        let types = Dictionary(now, uniquingKeysWith: { first, _ in first })
        for case .record(let item) in items {
            if stableOnly, item["stability"] == .string("experimental") { continue }
            guard case .string(let name)? = item[key], case .string(let type)? = item["type"] else { continue }
            #expect(types[name] == type || Self.grows(type, into: types[name]), "\(file.lastPathComponent): \(label) '\(name)' was \(type), is \(types[name] ?? "gone")")
        }
    }
}
