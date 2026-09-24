import Testing
import Foundation
import ApolloBase
@testable import ApolloConfig

@Suite("StateFiles")
struct StateFilesTests {
    static func paths() -> ConfigPaths {
        ConfigPaths(
            builtinConfigs: URL(fileURLWithPath: "/builtin"),
            userConfig: URL(fileURLWithPath: "/config"),
            applicationSupport: URL(fileURLWithPath: "/support")
        )
    }

    static func decl(_ name: String, _ type: ValueType) -> VarDecl {
        VarDecl(
            name: name,
            type: type,
            defaultValue: .scalar(CompiledValue(template: .literal(""), dependencies: [], span: .synthetic())),
            persist: true,
            derived: nil,
            span: .synthetic()
        )
    }

    @Test("Keine Statusdatei: leere Werte, keine Diagnosen")
    func noStateFileGivesEmptyValues() {
        let fs = MemoryFileSystem([:])
        let (values, diagnostics) = StateFiles.load(configID: "apolloshell-default", declarations: [], paths: Self.paths(), fileSystem: fs)
        #expect(values.isEmpty)
        #expect(diagnostics.isEmpty)
        #expect(!fs.exists(URL(fileURLWithPath: "/config/state/apolloshell-default.kdl.unreadable")))
    }

    @Test("Gueltige Statusdatei wird gelesen")
    func validStateFileIsRead() {
        let fs = MemoryFileSystem(["/config/state/apolloshell-default.kdl": "dashboard-tab \"media\"\n"])
        let (values, diagnostics) = StateFiles.load(
            configID: "apolloshell-default",
            declarations: [Self.decl("dashboard-tab", .string)],
            paths: Self.paths(),
            fileSystem: fs
        )
        #expect(values["dashboard-tab"] == .string("media"))
        #expect(diagnostics.isEmpty)
    }

    @Test("Kaputte Statusdatei wird als .kdl.unreadable kopiert")
    func brokenStateFileIsCopied() {
        let fs = MemoryFileSystem(["/config/state/apolloshell-default.kdl": "dashboard-tab \"unterminated"])
        let (_, diagnostics) = StateFiles.load(
            configID: "apolloshell-default",
            declarations: [Self.decl("dashboard-tab", .string)],
            paths: Self.paths(),
            fileSystem: fs
        )
        #expect(diagnostics.contains { $0.severity == .warning })
        #expect(fs.exists(URL(fileURLWithPath: "/config/state/apolloshell-default.kdl.unreadable")))
        let copy = try? fs.read(URL(fileURLWithPath: "/config/state/apolloshell-default.kdl.unreadable"))
        #expect(copy == "dashboard-tab \"unterminated")
    }

    @Test("Verworfener Wert wegen falschem Typ wird kopiert")
    func discardedValueDueToWrongTypeIsCopied() {
        let fs = MemoryFileSystem(["/config/state/apolloshell-default.kdl": "dashboard-tab 5\n"])
        let (values, diagnostics) = StateFiles.load(
            configID: "apolloshell-default",
            declarations: [Self.decl("dashboard-tab", .string)],
            paths: Self.paths(),
            fileSystem: fs
        )
        #expect(values["dashboard-tab"] == nil)
        #expect(diagnostics.contains { $0.severity == .warning })
        #expect(fs.exists(URL(fileURLWithPath: "/config/state/apolloshell-default.kdl.unreadable")))
    }

    @Test("Unbekannter Knoten bleibt stehen, keine Kopie")
    func unknownNodeStaysWithoutCopy() {
        let fs = MemoryFileSystem(["/config/state/apolloshell-default.kdl": "legacy-thing 1\n"])
        let (values, diagnostics) = StateFiles.load(
            configID: "apolloshell-default",
            declarations: [],
            paths: Self.paths(),
            fileSystem: fs
        )
        #expect(values.isEmpty)
        #expect(diagnostics.isEmpty)
        #expect(!fs.exists(URL(fileURLWithPath: "/config/state/apolloshell-default.kdl.unreadable")))
    }

    @Test("Zwei Configs haben getrennte Statusdateien")
    func twoConfigsHaveSeparateStateFiles() {
        let fs = MemoryFileSystem([
            "/config/state/apolloshell-default.kdl": "dashboard-tab \"media\"\n",
            "/config/state/user.kdl": "dashboard-tab \"performance\"\n",
        ])
        let declarations = [Self.decl("dashboard-tab", .string)]
        let (defaultValues, _) = StateFiles.load(configID: "apolloshell-default", declarations: declarations, paths: Self.paths(), fileSystem: fs)
        let (userValues, _) = StateFiles.load(configID: "user", declarations: declarations, paths: Self.paths(), fileSystem: fs)
        #expect(defaultValues["dashboard-tab"] == .string("media"))
        #expect(userValues["dashboard-tab"] == .string("performance"))
    }
}
