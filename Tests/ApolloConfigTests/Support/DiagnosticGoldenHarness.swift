import Testing
import Foundation
import ApolloBase
@testable import ApolloConfig

enum DiagnosticGolden {
    static let rewriteEnvironmentKey = "APOLLOSHELL_REWRITE_GOLDEN"
    static let fixturesPlaceholder = "<fixtures>"

    static func fixturesRoot(_ file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ApolloConfig/diagnostics")
    }

    static func sources(for name: String) -> [String: String] {
        let directory = fixturesRoot().appendingPathComponent(name)
        let disk = DiskFileSystem()
        var result: [String: String] = [:]
        guard let entries = try? disk.contentsOfDirectory(directory) else { return result }
        for entry in entries where entry.pathExtension == "kdl" {
            if let text = try? disk.read(entry) {
                result[entry.path] = text
            }
        }
        return result
    }

    static func file(_ name: String, _ relativePath: String) -> String {
        fixturesRoot().appendingPathComponent(name).appendingPathComponent(relativePath).path
    }

    static func verify(_ name: String, diagnostics: [Diagnostic], home: String? = nil, sourceLocation: SourceLocation = #_sourceLocation) {
        let text = DiagnosticFormatter.consoleText(diagnostics, sources: { sources(for: name)[$0] }, home: home)
        let normalizedText = text.replacingOccurrences(of: fixturesRoot().path, with: fixturesPlaceholder)
        let expectedPath = fixturesRoot().appendingPathComponent(name).appendingPathComponent("expected.txt")
        let disk = DiskFileSystem()
        if ProcessInfo.processInfo.environment[rewriteEnvironmentKey] == "1" {
            try? disk.write(normalizedText, to: expectedPath)
        }
        let expected = (try? disk.read(expectedPath)) ?? ""
        #expect(normalizedText == expected, sourceLocation: sourceLocation)
    }
}
