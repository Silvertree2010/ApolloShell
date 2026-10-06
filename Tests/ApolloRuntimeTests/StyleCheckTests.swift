import Testing
import Foundation
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

@Suite("apollo check: CSS")
struct StyleCheckTests {
    @Test("ungültige Werte und unbekannte Eigenschaften im Stylesheet werden gemeldet")
    func reports() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let css = dir.appendingPathComponent("style.css")
        try "#p { -apollo-appear: fade, scale(0.9); colr: red; }".write(to: css, atomically: true, encoding: .utf8)
        let ir = ConfigIR(id: "t", root: dir, styleSheets: [StyleRef(url: css, span: SourceSpan(file: css.path, start: SourcePosition(offset: 0, line: 1, column: 1), end: SourcePosition(offset: 0, line: 1, column: 1)))])
        let found = StyleCheck.run(ir)
        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.span?.file == css.path })
    }
}
