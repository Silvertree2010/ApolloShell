import Testing
import Foundation
import ApolloBase
import ApolloKDL
@testable import ApolloConfig

@Suite("IncludeExpander")
struct IncludeExpanderTests {
    static func paths(builtin: String = "/builtin", packages: String = "/config/packages") -> ConfigPaths {
        ConfigPaths(
            builtinConfigs: URL(fileURLWithPath: builtin),
            userConfig: URL(fileURLWithPath: "/config"),
            applicationSupport: URL(fileURLWithPath: "/support")
        )
    }

    func names(_ nodes: [ExpandedNode]) -> [String] {
        nodes.map(\.kdl.name)
    }

    @Test("Relativer include setzt Knoten an seine Stelle")
    func relativeInclude() {
        let files = [
            "/config/shell.kdl": "include \"sidebar.kdl\"\ndock {}",
            "/config/sidebar.kdl": "panel \"sidebar\" {}",
        ]
        let fs = MemoryFileSystem(files)
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.isEmpty)
        #expect(names(result.nodes) == ["panel", "dock"])
        #expect(result.files.count == 2)
    }

    @Test("include innerhalb eines Blocks wird Kind des Blocks")
    func includeInBlock() {
        let files = [
            "/config/shell.kdl": "column {\n  include \"modules.kdl\"\n}",
            "/config/modules.kdl": "text \"a\"\ntext \"b\"",
        ]
        let fs = MemoryFileSystem(files)
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.isEmpty)
        #expect(names(result.nodes) == ["column"])
        #expect(names(result.nodes[0].children) == ["text", "text"])
    }

    @Test("Glob bindet sortiert ein und ueberspringt Punktdateien")
    func globSorted() {
        let files = [
            "/config/shell.kdl": "include \"dashboard/*.kdl\"",
            "/config/dashboard/weather.kdl": "weather {}",
            "/config/dashboard/clock.kdl": "clock {}",
            "/config/dashboard/.hidden.kdl": "hidden {}",
        ]
        let fs = MemoryFileSystem(files)
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.isEmpty)
        #expect(names(result.nodes) == ["clock", "weather"])
    }

    @Test("Glob ohne Treffer warnt, optional bleibt still")
    func globNoMatch() {
        let fs1 = MemoryFileSystem(["/config/shell.kdl": "include \"dashboard/*.kdl\""])
        let result1 = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs1, paths: Self.paths())
        #expect(result1.diagnostics.count == 1)
        #expect(result1.diagnostics[0].severity == .warning)

        let fs2 = MemoryFileSystem(["/config/shell.kdl": "include \"dashboard/*.kdl\" optional=#true"])
        let result2 = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs2, paths: Self.paths())
        #expect(result2.diagnostics.isEmpty)
    }

    @Test("Fehlende Datei ohne optional ist ein Fehler")
    func missingFileFails() {
        let fs = MemoryFileSystem(["/config/shell.kdl": "include \"missing.kdl\""])
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .error)
    }

    @Test("Fehlende optionale Datei ist kein Fehler")
    func missingOptionalFileSucceeds() {
        let fs = MemoryFileSystem(["/config/shell.kdl": "include \"missing.kdl\" optional=#true"])
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.isEmpty)
        #expect(result.nodes.isEmpty)
    }

    @Test("builtin: liest aus einer eingebauten Config")
    func builtinInclude() {
        let files = [
            "/config/shell.kdl": "include \"builtin:apolloshell-default/sidebar.kdl\"",
            "/builtin/apolloshell-default/sidebar.kdl": "panel \"sidebar\" {}",
        ]
        let fs = MemoryFileSystem(files)
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.isEmpty)
        #expect(names(result.nodes) == ["panel"])
    }

    @Test("pkg: liest aus dem Paketordner")
    func pkgInclude() {
        let files = [
            "/config/shell.kdl": "include \"pkg:weather-cards/cards.kdl\"",
            "/config/packages/weather-cards/cards.kdl": "card {}",
        ]
        let fs = MemoryFileSystem(files)
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.isEmpty)
        #expect(names(result.nodes) == ["card"])
    }

    @Test("Paket darf nicht in $CONFIG greifen")
    func packageCannotReachConfig() {
        let files = [
            "/config/shell.kdl": "include \"pkg:weather-cards/cards.kdl\"",
            "/config/packages/weather-cards/cards.kdl": "include \"../../shell-secret.kdl\"",
            "/config/shell-secret.kdl": "secret {}",
        ]
        let fs = MemoryFileSystem(files)
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.contains { $0.severity == .error && $0.message.contains("escapes") })
        #expect(result.nodes.isEmpty)
    }

    @Test("Paket darf auf builtin: greifen")
    func packageCanReachBuiltin() {
        let files = [
            "/config/shell.kdl": "include \"pkg:weather-cards/cards.kdl\"",
            "/config/packages/weather-cards/cards.kdl": "include \"builtin:apolloshell-default/shared.kdl\"",
            "/builtin/apolloshell-default/shared.kdl": "shared {}",
        ]
        let fs = MemoryFileSystem(files)
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.isEmpty)
        #expect(names(result.nodes) == ["shared"])
    }

    @Test("Paket darf nicht in ein anderes Paket greifen")
    func packageCannotReachOtherPackage() {
        let files = [
            "/config/shell.kdl": "include \"pkg:a/entry.kdl\"",
            "/config/packages/a/entry.kdl": "include \"pkg:b/other.kdl\"",
            "/config/packages/b/other.kdl": "other {}",
        ]
        let fs = MemoryFileSystem(files)
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.contains { $0.severity == .error && $0.message.contains("same package") })
    }

    @Test("Zwei Punkte ueber die Wurzel hinaus sind ein Fehler")
    func dotDotAboveRoot() {
        let fs = MemoryFileSystem(["/config/shell.kdl": "include \"../outside.kdl\""])
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.contains { $0.severity == .error && $0.message.contains("escapes") })
    }

    @Test("Absoluter Pfad ist ein Fehler")
    func absolutePathFails() {
        let fs = MemoryFileSystem(["/config/shell.kdl": "include \"/etc/passwd\""])
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.contains { $0.severity == .error && $0.message.contains("relative") })
    }

    @Test("Tilde ist ein Fehler")
    func tildePathFails() {
        let fs = MemoryFileSystem(["/config/shell.kdl": "include \"~/shell.kdl\""])
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.contains { $0.severity == .error && $0.message.contains("~") })
    }

    @Test("Symlink nach aussen ist ein Fehler")
    func symlinkEscapesConfig() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let configDir = directory.appendingPathComponent("config")
        let outsideDir = directory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "include \"escape.kdl\"".write(to: configDir.appendingPathComponent("shell.kdl"), atomically: true, encoding: .utf8)
        try "secret {}".write(to: outsideDir.appendingPathComponent("secret.kdl"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: configDir.appendingPathComponent("escape.kdl"),
            withDestinationURL: outsideDir.appendingPathComponent("secret.kdl")
        )
        let fs = DiskFileSystem()
        let result = IncludeExpander.expand(root: configDir, origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.contains { $0.severity == .error && $0.message.contains("symlink") })
    }

    @Test("Zyklus A -> B -> C -> A meldet die ganze Kette")
    func cycleReportsChain() {
        let files = [
            "/config/shell.kdl": "include \"a.kdl\"",
            "/config/a.kdl": "include \"b.kdl\"",
            "/config/b.kdl": "include \"c.kdl\"",
            "/config/c.kdl": "include \"a.kdl\"",
        ]
        let fs = MemoryFileSystem(files)
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        let cycleDiagnostics = result.diagnostics.filter { $0.message.contains("include cycle") }
        #expect(cycleDiagnostics.count == 1)
        #expect(cycleDiagnostics[0].message.contains("a.kdl"))
        #expect(cycleDiagnostics[0].message.contains("c.kdl"))
    }

    @Test("Selbst-include in einem Block ist ein Zyklus")
    func selfIncludeInBlock() {
        let files = ["/config/shell.kdl": "column {\n  include \"shell.kdl\"\n}"]
        let fs = MemoryFileSystem(files)
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.contains { $0.message.contains("include cycle") })
    }

    @Test("Dieselbe Datei zweimal einzubinden ist erlaubt")
    func sameFileTwice() {
        let files = [
            "/config/shell.kdl": "include \"module.kdl\"\ninclude \"module.kdl\"",
            "/config/module.kdl": "text \"x\"",
        ]
        let fs = MemoryFileSystem(files)
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.isEmpty)
        #expect(names(result.nodes) == ["text", "text"])
    }

    @Test("Doppel-include-Kette trifft die 64er-Grenze frueh und sauber")
    func doubleIncludeChainHitsLimitCleanly() {
        var files: [String: String] = ["/config/shell.kdl": "include \"f0.kdl\""]
        for index in 0..<8 {
            files["/config/f\(index).kdl"] = "include \"f\(index + 1).kdl\"\ninclude \"f\(index + 1).kdl\""
        }
        files["/config/f8.kdl"] = "leaf {}"
        let fs = MemoryFileSystem(files)
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        let limitDiagnostics = result.diagnostics.filter { $0.message.contains("more than 64 files") }
        #expect(limitDiagnostics.count == 1)
    }

    @Test("Datei ueber 1 MiB ist ein Fehler")
    func fileOverOneMebibyteFails() {
        let big = String(repeating: "a", count: KDLLimits.maxBytes + 1)
        let files = ["/config/shell.kdl": "include \"big.kdl\"", "/config/big.kdl": "text \"\(big)\""]
        let fs = MemoryFileSystem(files)
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.contains { $0.severity == .error && $0.message.contains("bytes") })
    }

    @Test("Ausdruck im Pfad ist ein Fehler")
    func expressionInPathFails() {
        let fs = MemoryFileSystem(["/config/shell.kdl": "include \"{var.name}.kdl\""])
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.contains { $0.severity == .error && $0.message.contains("expression") })
    }

    @Test("Typannotationen sind ein Fehler")
    func typeAnnotationsAreErrors() {
        let fs = MemoryFileSystem(["/config/shell.kdl": "text (str)\"hi\""])
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.contains { $0.severity == .error && $0.message == "type annotations are reserved" })
    }

    @Test("Parse-Fehler in eingebundener Datei traegt die Kette")
    func parseErrorCarriesChain() {
        let files = [
            "/config/shell.kdl": "include \"broken.kdl\"",
            "/config/broken.kdl": "panel \"x\" {",
        ]
        let fs = MemoryFileSystem(files)
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.count == 1)
        #expect(!result.diagnostics[0].notes.isEmpty)
        #expect(result.diagnostics[0].notes[0].message.contains("included from"))
    }

    @Test("Tiefe Verschachtelung ueber include in Bloecken ohne Stapel-Ueberlauf")
    func deepNestingAcrossIncludes() {
        func nested(_ levels: Int, innermost: String) -> String {
            var text = innermost
            for _ in 0..<levels {
                text = "column {\n\(text)\n}"
            }
            return text
        }
        let files: [String: String] = [
            "/config/shell.kdl": nested(40, innermost: "include \"deeper.kdl\""),
            "/config/deeper.kdl": nested(40, innermost: "leaf {}"),
        ]
        let fs = MemoryFileSystem(files)
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: Self.paths())
        #expect(result.diagnostics.contains { $0.message.contains("nested deeper") })
    }
}
