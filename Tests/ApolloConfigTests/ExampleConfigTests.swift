import Testing
import Foundation
import ApolloBase
@testable import ApolloConfig

@Suite("Beispiel-Configs aus docs/GUIDE.md")
struct ExampleConfigTests {
    static let examples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("examples/configs")

    static var names: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: examples.path)) ?? []).sorted()
    }

    @Test("Jede Beispiel-Config lädt ohne eine einzige Diagnose")
    func examplesLoadCleanly() {
        #expect(Self.names.count >= 5)
        for name in Self.names {
            let root = Self.examples.appendingPathComponent(name)
            let paths = ConfigPaths(builtinConfigs: URL(fileURLWithPath: "/nonexistent/builtin"), userConfig: Self.examples, applicationSupport: URL(fileURLWithPath: "/nonexistent/support"))
            let loader = ConfigLoader(fileSystem: DiskFileSystem(), paths: paths, registry: .builtin, filters: .builtin, shellVersion: ShellVersion.current)
            let result = loader.load(ConfigLocation(id: name, root: root, isBuiltin: false))
            #expect(result.ir != nil, "\(name)")
            #expect(result.diagnostics.map(\.message) == [], "\(name)")
        }
    }
}
