import Testing
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

@MainActor
@Suite("Provider-Einstellungen aus der Config")
struct ProviderSettingsTests {
    @Test("Ein Provider-Block kommt per configure an und folgt seinem Ausdruck")
    func settingsReachProvider() async throws {
        let shell = KDLShell()
        let power = StubProvider(id: "power")
        shell.fixture.providers.register(power)
        shell.apply(try await shell.load("""
        var lid #false
        power lid-closed="{var.lid}"
        panel "bar" { text "bar" }
        """))
        shell.fixture.flush()
        #expect(power.configuredSettings.last?["lid-closed"] == .bool(false))
        _ = shell.vars.set("lid", .bool(true), for: nil)
        shell.fixture.flush()
        #expect(power.configuredSettings.last?["lid-closed"] == .bool(true))
    }

    @Test("Ohne Block bekommt der Provider beim Reload leere Einstellungen")
    func removedBlockClears() async throws {
        let shell = KDLShell()
        let power = StubProvider(id: "power")
        shell.fixture.providers.register(power)
        shell.apply(try await shell.load("""
        power lid-closed=#true
        panel "bar" { text "bar" }
        """))
        shell.fixture.flush()
        #expect(power.configuredSettings.last?["lid-closed"] == .bool(true))
        shell.apply(try await shell.load("panel \"bar\" { text \"bar\" }\n"))
        shell.fixture.flush()
        #expect(power.configuredSettings.last?["lid-closed"] == nil)
    }
}
