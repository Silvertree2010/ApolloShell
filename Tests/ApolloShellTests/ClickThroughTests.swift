import Testing
import AppKit
import ApolloConfig
import ApolloRuntime
@testable import ApolloShell

@MainActor
@Suite("click-through \"auto\": Host schaltet Mausereignisse nach Zeigerlage (Entscheid 38)")
struct ClickThroughTests {
    static func fixture() throws -> (HostFixture, FakeWindow, String, Identity, () -> Int) {
        let fixture = try HostFixture("popup \"stack\" anchor=\"top-left\" click-through=\"auto\" { column { text \"a\" } }")
        var watchers = 0, stopped = 0
        fixture.host.watchPointer = { _ in
            watchers += 1
            return { stopped += 1 }
        }
        fixture.assembly.runtime.open("stack", screenKey: nil)
        fixture.flush()
        let window = try #require(fixture.window("stack"))
        let key = SurfaceHost.key("stack", HostFixture.screen.key)
        let surface = try #require(fixture.host.model.surfaces[key])
        let identity = try #require(surface.root.first?.identity)
        return (fixture, window, key, identity, { watchers - stopped })
    }

    @Test("über einer Trefferfläche nimmt das Fenster Klicks an, daneben gehen sie durch")
    func followsPointer() throws {
        let (fixture, window, key, identity, active) = try Self.fixture()
        window.setFrame(CGRect(x: 100, y: 500, width: 200, height: 100))
        #expect(active() == 1)
        fixture.host.pointer = { CGPoint(x: 120, y: 590) }
        fixture.host.context?.hits.update([HitRegion(identity: identity, frame: CGRect(x: 0, y: 0, width: 50, height: 20))], surfaceKey: key)
        #expect(window.ignoresMouse == false)
        fixture.host.pointer = { CGPoint(x: 250, y: 520) }
        fixture.host.pointerMoved()
        #expect(window.ignoresMouse == true)
        fixture.host.pointer = { CGPoint(x: 10, y: 10) }
        fixture.host.pointerMoved()
        #expect(window.ignoresMouse == true)
    }

    @Test("Zeiger-Beobachtung läuft nur, solange eine auto-Oberfläche sichtbar ist")
    func watchesOnlyWhileShown() throws {
        let (fixture, _, _, _, active) = try Self.fixture()
        #expect(active() == 1)
        fixture.assembly.runtime.close("stack", screenKey: HostFixture.screen.key)
        fixture.flush()
        #expect(active() == 0)
    }
}
