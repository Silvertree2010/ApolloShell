import Foundation
import Testing
@testable import ApolloStyle

@Suite("CSS-Eigenschaften: Registry, Doku und Renderer")
struct CSSPropertyPromiseTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func read(_ path: String) throws -> String {
        String(decoding: try Data(contentsOf: root.appendingPathComponent(path)), as: UTF8.self)
    }

    static func sources(in folder: String) throws -> String {
        let base = root.appendingPathComponent(folder)
        let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        return try files.map { String(decoding: try Data(contentsOf: $0), as: UTF8.self) }.joined(separator: "\n")
    }

    @Test("Jede -apollo-Eigenschaft der Registry steht in docs/THEMES.md, und die Tabelle nennt keine anderen")
    func apolloPropertiesAreDocumented() throws {
        let text = try Self.read("docs/THEMES.md")
        var documented: Set<String> = []
        for line in text.split(separator: "\n") where line.hasPrefix("| `-apollo-") {
            let name = line.dropFirst(3).prefix { $0 != "`" }
            documented.insert(String(name))
        }
        let registered = Set(CSSPropertyRegistry.builtin.keys.filter { $0.hasPrefix("-apollo-") })
        #expect(registered.subtracting(documented).sorted() == [])
        #expect(documented.subtracting(registered).sorted() == [])
    }

    @Test("Jede CSS-Eigenschaft der Registry wird vom Renderer oder beim Zusammenführen gelesen")
    func everyPropertyHasAReader() throws {
        let readers = try Self.sources(in: "Sources/ApolloShell") + "\n" + Self.read("Sources/ApolloStyle/StyleFinisher.swift")
        var missing: [String] = []
        for name in CSSPropertyRegistry.builtin.keys.sorted() {
            if let box = ["padding", "margin"].first(where: { name.hasPrefix($0 + "-") }),
               CSSBoxProperties.sides.contains(String(name.dropFirst(box.count + 1))) {
                if !readers.contains("\"\(box)\"") || !readers.contains("\\(box)-\\($0)") { missing.append(name) }
                continue
            }
            if !readers.contains("\"\(name)\"") { missing.append(name) }
        }
        #expect(missing == [])
    }
}
