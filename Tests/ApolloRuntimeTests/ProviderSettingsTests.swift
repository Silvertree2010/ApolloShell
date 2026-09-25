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

    @Test("Laden und Reload: genau ein vollständiger configure, verschobene Zeilen lösen keinen neuen aus")
    func oneCompleteConfigure() async throws {
        let shell = KDLShell()
        let power = StubProvider(id: "power")
        shell.fixture.providers.register(power)
        shell.apply(try await shell.load("""
        var lid #true
        power lid-closed="{var.lid}"
        panel "bar" { text "bar" }
        """))
        shell.fixture.flush()
        #expect(power.configuredSettings.count == 1)
        #expect(power.configuredSettings.first?["lid-closed"] == .bool(true))
        shell.apply(try await shell.load("""
        var lid #true

        power lid-closed="{var.lid}"
        panel "bar" { text "bar" }
        """))
        shell.fixture.flush()
        #expect(power.configuredSettings.count == 1)
    }

    @Test("poll- und listen-Blöcke kommen je Name an den Provider")
    func namedBlocks() async throws {
        let shell = KDLShell()
        let poll = StubProvider(id: "poll")
        shell.fixture.providers.register(poll)
        shell.apply(try await shell.load("""
        var show #true
        poll "vpn" command="scutil --nc status" interval="10s"
        poll "brew" command="brew outdated" when="{var.show}"
        panel "bar" { text "{poll.vpn}" }
        """))
        shell.fixture.flush()
        let settings = try #require(poll.configuredSettings.last)
        guard case .record(let vpn)? = settings["vpn"], case .record(let brew)? = settings["brew"] else {
            Issue.record("no named records in \(settings)")
            return
        }
        #expect(vpn["command"] == .string("scutil --nc status"))
        #expect(vpn["interval"] == .string("10s"))
        #expect(brew["when"] == .bool(true))
        _ = shell.vars.set("show", .bool(false), for: nil)
        shell.fixture.flush()
        guard case .record(let changed)? = poll.configuredSettings.last?["brew"] else { return }
        #expect(changed["when"] == .bool(false))
    }

    @Test("screen= als Ausdruck: Änderung baut die Instanzen live um")
    func screenExpressionIsLive() async throws {
        let shell = KDLShell()
        shell.apply(try await shell.load("""
        var where "all"
        panel "bar" screen="{var.where}" { text "bar" }
        """), screens: ["A", "B"])
        shell.fixture.flush()
        #expect(shell.runtime.surface("bar", screenKey: "A") != nil && shell.runtime.surface("bar", screenKey: "B") != nil)
        _ = shell.vars.set("where", .string("main"), for: nil)
        shell.fixture.flush()
        #expect(shell.runtime.surface("bar", screenKey: "A") != nil && shell.runtime.surface("bar", screenKey: "B") == nil)
        _ = shell.vars.set("where", .string("all"), for: nil)
        shell.fixture.flush()
        #expect(shell.runtime.surface("bar", screenKey: "A") != nil && shell.runtime.surface("bar", screenKey: "B") != nil)
    }

    @Test("Neu gebaute Oberfläche auf einem Bildschirm mit Vollbild-App bleibt versteckt")
    func newSurfaceInheritsFullscreen() async throws {
        let shell = KDLShell()
        shell.apply(try await shell.load("""
        var where "main"
        panel "bar" screen="{var.where}" { text "bar" }
        """), screens: ["A", "B"])
        shell.fixture.flush()
        shell.runtime.setHiddenByFullscreen(true, screenKey: "B")
        _ = shell.vars.set("where", .string("all"), for: nil)
        shell.fixture.flush()
        let instance = try #require(shell.runtime.surface("bar", screenKey: "B"))
        #expect(instance.isVisible == false)
    }
}
