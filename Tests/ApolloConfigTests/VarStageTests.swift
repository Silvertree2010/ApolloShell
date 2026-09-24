import Testing
import Foundation
import ApolloBase
@testable import ApolloConfig

@Suite("VarStage")
struct VarStageTests {
    static func expand(_ text: String) -> [ExpandedNode] {
        let fs = MemoryFileSystem(["/config/shell.kdl": text])
        let paths = ConfigPaths(
            builtinConfigs: URL(fileURLWithPath: "/builtin"),
            userConfig: URL(fileURLWithPath: "/config"),
            applicationSupport: URL(fileURLWithPath: "/support")
        )
        let result = IncludeExpander.expand(root: URL(fileURLWithPath: "/config"), origin: .user, fileSystem: fs, paths: paths)
        #expect(result.diagnostics.isEmpty)
        return result.nodes
    }

    static func run(_ text: String) -> VarStageResult {
        VarStage.run(Self.expand(text), registry: .builtin)
    }

    static func literal(_ template: ValueTemplate) -> Value? {
        guard case .scalar(let compiled) = template, case .whole(.literal(let value)) = compiled.template else { return nil }
        return value
    }

    @Test("Skalares var mit Vorgabe")
    func scalarVarWithDefault() {
        let result = Self.run("var launcher-selection 0")
        #expect(result.diagnostics.isEmpty)
        #expect(result.declarations.count == 1)
        let decl = result.declarations[0]
        #expect(decl.name == "launcher-selection")
        #expect(decl.type == .number)
        #expect(Self.literal(decl.defaultValue) == .number(0))
        #expect(decl.persist == false)
        #expect(decl.derived == nil)
    }

    @Test("var mit persist=#true")
    func varWithPersist() {
        let result = Self.run("var dashboard-tab \"dashboard\" persist=#true")
        #expect(result.diagnostics.isEmpty)
        #expect(result.declarations[0].persist == true)
        #expect(result.declarations[0].type == .string)
    }

    @Test("var mit strukturierter Liste als Vorgabe")
    func varWithStructuredListDefault() {
        let result = Self.run("var sidebar-modules persist=#true {\n  - kind=\"dashboard-button\"\n  - kind=\"dock\" show-running=#true icon-size=\"medium\"\n}")
        #expect(result.diagnostics.isEmpty)
        let decl = result.declarations[0]
        #expect(decl.type == .list)
        guard case .list(let items) = decl.defaultValue else {
            Issue.record("expected a list template")
            return
        }
        #expect(items.count == 2)
    }

    @Test("var mit type= explizit")
    func varWithExplicitType() {
        let result = Self.run("var flag #null type=\"bool\"")
        #expect(result.diagnostics.isEmpty)
        #expect(result.declarations[0].type == .bool)
    }

    @Test("var mit falschem type= ist ein Fehler")
    func varWithInvalidTypeFails() {
        let result = Self.run("var flag #true type=\"octal\"")
        #expect(result.diagnostics.contains { $0.severity == .error })
    }

    @Test("var mit from= wird abgeleitet")
    func varWithFromIsDerived() {
        let result = Self.run("var launcher-results from=\"{apps.all}\"")
        #expect(result.diagnostics.isEmpty)
        #expect(result.declarations[0].derived != nil)
    }

    @Test("var mit from= und persist ist ein Fehler")
    func varWithFromAndPersistFails() {
        let result = Self.run("var launcher-results from=\"{apps.all}\" persist=#true")
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .error)
        #expect(result.diagnostics[0].message.contains("persist"))
    }

    @Test("var ohne Namen ist ein Fehler")
    func varWithoutNameFails() {
        let result = Self.run("var 5")
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].severity == .error)
    }

    @Test("var launcher-key wie in 7.4 mit shell.fresh-install")
    func varLikeSection74Example() {
        let result = Self.run("var launcher-key \"{shell.fresh-install ? 'alt+space' : 'f20'}\" persist=#true")
        #expect(result.diagnostics.isEmpty)
        #expect(result.declarations[0].persist == true)
    }
}
