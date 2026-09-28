import Testing
import Foundation
import ApolloBase
@testable import ApolloConfig

@Suite("Kennungen der Diagnosen")
struct DiagnosticCodeTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test("jede Kennung ist A und drei Ziffern, aufsteigend, mit einem Satz Erklärung")
    func codesAreWellFormed() {
        let raw = DiagnosticCode.allCases.map(\.rawValue)
        #expect(raw == raw.sorted())
        for code in DiagnosticCode.allCases {
            #expect(code.rawValue.wholeMatch(of: /A[0-9]{3}/) != nil, "\(code.rawValue)")
            #expect(code.summary.split(separator: " ").count >= 3, "\(code.rawValue): \(code.summary)")
            #expect(code.summary.hasSuffix("."), "\(code.rawValue): \(code.summary)")
        }
    }

    @Test("die Kennung steht in der Kopfzeile, ohne Kennung bleibt sie wie bisher")
    func headerCarriesCode() {
        let span = SourceSpan(file: "shell.kdl", start: SourcePosition(offset: 0, line: 2, column: 3), end: SourcePosition(offset: 0, line: 2, column: 5))
        let coded = DiagnosticFormatter.format(Diagnostic(.error, "unknown node 'txt'", span: span, code: .unknownNode), sourceText: { _ in nil })
        #expect(coded == "shell.kdl:2:3: error[A201]: unknown node 'txt'")
        let plain = DiagnosticFormatter.format(Diagnostic(.warning, "something"), sourceText: { _ in nil })
        #expect(plain == "warning: something")
    }

    @Test("ein Tippfehler in der Config meldet A201, ein fehlendes include A102")
    func loaderSetsCodes() {
        let unknown = Self.load("panel \"bar\" {\n    txt \"hi\"\n}\n")
        #expect(unknown.diagnostics.contains { $0.code == .unknownNode })
        let missing = Self.load("include \"nope.kdl\"\n")
        #expect(missing.diagnostics.contains { $0.code == .includeNotFound })
    }

    static func load(_ shell: String) -> ConfigLoadResult {
        let paths = ConfigPaths(builtinConfigs: URL(fileURLWithPath: "/builtin"), userConfig: URL(fileURLWithPath: "/config"), applicationSupport: URL(fileURLWithPath: "/support"))
        let loader = ConfigLoader(fileSystem: MemoryFileSystem(["/config/shell.kdl": shell]), paths: paths, registry: .builtin, filters: .builtin, shellVersion: "0.2.0")
        return loader.load(ConfigLocation(id: "mine", root: URL(fileURLWithPath: "/config"), isBuiltin: false))
    }

    @Test("jede Diagnose in ApolloConfig und ApolloStyle trägt eine Kennung")
    func everyLoaderDiagnosticHasCode() throws {
        for module in ["ApolloConfig", "ApolloStyle"] {
            let folder = Self.root.appendingPathComponent("Sources/\(module)")
            let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)!.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
            #expect(!files.isEmpty)
            for file in files {
                let text = try String(contentsOf: file, encoding: .utf8)
                var rest = Substring(text)
                while let range = rest.range(of: "Diagnostic(") {
                    let before = rest[..<range.lowerBound].last
                    rest = rest[range.upperBound...]
                    if let before, before.isLetter || before.isNumber { continue }
                    let call = Self.call(rest)
                    #expect(call.contains("code: ."), "\(file.lastPathComponent): Diagnostic(\(call.prefix(80))")
                }
            }
        }
    }

    @Test("docs/DIAGNOSTICS.md entspricht dem Katalog")
    func docsMatchCatalog() throws {
        let file = try String(contentsOf: Self.root.appendingPathComponent("docs/DIAGNOSTICS.md"), encoding: .utf8)
        #expect(file == DiagnosticCode.markdown)
    }

    static func call(_ text: Substring) -> Substring {
        var depth = 1
        var inString = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\\" {
                index = text.index(after: index)
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == "(" { depth += 1 }
                if character == ")" {
                    depth -= 1
                    if depth == 0 { return text[..<index] }
                }
            }
            index = text.index(after: index)
        }
        return text
    }
}
