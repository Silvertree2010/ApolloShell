import Testing
import AppKit
import SwiftUI
import ApolloConfig
import ApolloRuntime
@testable import ApolloShell

@MainActor
@Suite("Host-Rückrufe des Renderers: Aufnahme und Flyout-Ausdehnung")
struct HostCallbacksTests {
    @Test("key-recorder nimmt auf: globale Kürzel ruhen, danach sind sie wieder da")
    func recordingSuspendsHotKeys() async throws {
        let harness = try ShellHarness("panel \"bar\" { row { text \"a\" } }\nbind \"ctrl+alt+k\" id=\"k\" { toggle \"bar\" }")
        try await harness.start()
        let registrar = try #require(harness.shell.registrar as? FakeRegistrar)
        let context = try #require(harness.shell.host.context)
        #expect(registrar.active.keys.contains("ctrl+alt+k"))
        context.onRecording(true)
        context.onRecording(true)
        #expect(registrar.active.isEmpty)
        context.onRecording(false)
        #expect(registrar.active.isEmpty)
        context.onRecording(false)
        #expect(registrar.active.keys.contains("ctrl+alt+k"))
    }

    @Test("Flyout wächst das Fenster sofort, schmal erst 0,5 s nach dem Schliessen; reserve zählt nur die Oberfläche")
    func flyoutGrowsWindow() throws {
        let fixture = try HostFixture("panel \"bar\" anchor=\"left\" reserve=#true { column { text \"a\" } }")
        let timers = ManualTimers()
        fixture.host.scheduleTimer = { timers.schedule($0, $1) }
        let window = try #require(fixture.window("bar"))
        let key = SurfaceHost.key("bar", HostFixture.screen.key)
        let before = window.frame
        let context = try #require(fixture.host.context)
        let fitting = window.fittingSize
        window.fittingSize = CGSize(width: fitting.width + 120, height: fitting.height)
        context.onFlyoutExtent(key, EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 120))
        fixture.flush()
        #expect(window.frame.width == before.width + 120)
        #expect(window.frame.minX == before.minX)
        #expect(fixture.host.reservedEdges()[HostFixture.screen.key]?.left == before.maxX)
        context.onFlyoutExtent(key, EdgeInsets())
        fixture.flush()
        #expect(window.frame.width == before.width + 120)
        #expect(timers.live == [0.5])
        window.fittingSize = fitting
        timers.fireNext()
        fixture.flush()
        #expect(window.frame == before)
    }
}
