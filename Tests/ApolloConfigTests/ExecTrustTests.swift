import Testing
import Foundation
import ApolloBase
@testable import ApolloConfig

@Suite("exec: Quoting und Paketgrenze")
struct ExecTrustTests {
    static func load(_ files: [String: String]) -> ConfigLoadResult {
        let root = URL(fileURLWithPath: "/t")
        let loader = ConfigLoader(fileSystem: MemoryFileSystem(files), paths: ConfigPaths(builtinConfigs: URL(fileURLWithPath: "/b"), userConfig: root, applicationSupport: root),
                                  registry: .builtin, filters: .builtin, shellVersion: ShellVersion.current)
        return loader.load(ConfigLocation(id: "t", root: root, isBuiltin: false))
    }

    @Test("shell-quote: ein Wort in einfachen Anführungszeichen, auch mit ' im Text")
    func quoteWord() {
        #expect(ShellQuote.word("a b") == "'a b'")
        #expect(ShellQuote.word("it's; rm -rf ~") == "'it'\\''s; rm -rf ~'")
        #expect(ShellQuote.word("") == "''")
    }

    @Test("exec: jeder Ausdruck wird durch shell-quote geleitet, wörtlicher Text bleibt")
    func execArgumentQuoted() throws {
        let result = Self.load(["/t/shell.kdl": "var x \"a\"\nbind \"f19\" { exec \"echo {var.x} | wc -c\" }\nbind \"f18\" { exec \"{var.x}\" }\n"])
        let ir = try #require(result.ir)
        func command(_ index: Int) -> StringTemplate? {
            guard case .call(let call)? = ir.binds[index].actions.first else { return nil }
            return call.arguments.first?.template
        }
        guard case .parts(let parts)? = command(0) else {
            Issue.record("no parts")
            return
        }
        #expect(parts.first == .text("echo "))
        #expect(parts.last == .text(" | wc -c"))
        guard case .expression(.pipe(_, let filter)) = parts[1] else {
            Issue.record("expression not quoted")
            return
        }
        #expect(filter.name == "shell-quote")
        guard case .whole(.pipe(_, let whole))? = command(1) else {
            Issue.record("whole expression not quoted")
            return
        }
        #expect(whole.name == "shell-quote")
        let literal = Self.load(["/t/shell.kdl": "bind \"f19\" { exec \"touch '/tmp/a b' && echo ok\" }\n"])
        guard case .call(let call)? = literal.ir?.binds.first?.actions.first, let template = call.arguments.first?.template else {
            Issue.record("no literal exec")
            return
        }
        switch template {
        case .literal(let text), .whole(.literal(.string(let text))):
            #expect(text == "touch '/tmp/a b' && echo ok")
        default:
            Issue.record("literal command was changed: \(template)")
        }
    }

    @Test("Pakete dürfen exec, open-url und poll nicht nutzen, die eigene Config schon")
    func packageCapability() {
        let user = Self.load(["/t/shell.kdl": "bind \"f19\" { exec \"true\" }\npoll \"x\" command=\"true\"\n"])
        #expect(user.ir != nil)
        let package = Self.load([
            "/t/shell.kdl": "include \"pkg:evil/x.kdl\"\n",
            "/t/packages/evil/x.kdl": "bind \"f19\" { exec \"true\" }\nbind \"f18\" { open-url \"https://example.com\" }\npoll \"x\" command=\"true\"\n",
        ])
        let messages = package.diagnostics.filter { $0.severity == .error }.map(\.message)
        #expect(messages.contains("package 'evil' may not use 'exec': it starts programs or controls apps"))
        #expect(messages.contains("package 'evil' may not use 'open-url': it starts programs or controls apps"))
        #expect(messages.contains("package 'evil' may not declare 'poll': it starts programs"))
    }
}
