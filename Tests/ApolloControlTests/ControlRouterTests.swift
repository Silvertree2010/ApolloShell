import Testing
import Foundation
import ApolloConfig
@testable import ApolloControl

@Suite("Router der Socket-Befehle", .serialized)
struct ControlRouterTests {
    @Test("fehlende Argumente sind ein Fehler mit Namen")
    func missingArguments() async throws {
        let harness = try CLIHarness()
        let router = ControlRouter(shell: harness.shell, configs: ConfigCatalog(paths: harness.paths, settings: harness.settings), themes: ThemeCatalog(paths: harness.paths, settings: harness.settings))
        guard case .failure(let message) = await router.reply(to: ControlRequest(id: 1, cmd: "get")) else {
            Issue.record("expected failure")
            return
        }
        #expect(message == "'get' needs a string 'name'")
    }

    @Test("set nimmt Zahlen nur endlich an")
    func setChecksNumbers() async throws {
        let harness = try CLIHarness()
        let router = ControlRouter(shell: harness.shell, configs: ConfigCatalog(paths: harness.paths, settings: harness.settings), themes: ThemeCatalog(paths: harness.paths, settings: harness.settings))
        _ = await router.reply(to: ControlRequest(id: 1, cmd: "set", args: Record([("name", .string("x")), ("value", .list([.number(.nan)]))])))
        #expect(harness.shell.calls == ["set x [null]"])
    }
}
