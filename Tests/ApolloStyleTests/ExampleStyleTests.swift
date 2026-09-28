import Testing
import Foundation
@testable import ApolloStyle

@Suite("Stylesheets der Beispiel-Configs")
struct ExampleStyleTests {
    @Test("Jedes style.css der Beispiele liest sich ohne Diagnose")
    func examplesParseCleanly() throws {
        let examples = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("examples/configs")
        let names = try FileManager.default.contentsOfDirectory(atPath: examples.path).sorted()
        #expect(names.count >= 5)
        for name in names {
            let file = examples.appendingPathComponent(name).appendingPathComponent("style.css")
            let text = try String(contentsOf: file, encoding: .utf8)
            let (sheet, diagnostics) = StyleSheet.parse(text, file: file.path, origin: .config)
            #expect(diagnostics.map(\.message) == [], "\(name)")
            #expect(!sheet.rules.isEmpty, "\(name)")
        }
    }
}
