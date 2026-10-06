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
        window.calls = []
        context.onFlyoutExtent(key, EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 120))
        fixture.flush()
        #expect(window.calls == ["content+frame"])
        #expect(window.frame.width == before.width + 120)
        #expect(window.frame.minX == before.minX)
        #expect(fixture.host.reservedEdges()[HostFixture.screen.key]?.left == before.maxX)
        context.onFlyoutExtent(key, EdgeInsets())
        fixture.flush()
        #expect(window.frame.width == before.width + 120)
        #expect(timers.live == [0.5])
        window.fittingSize = fitting
        window.calls = []
        timers.fireNext()
        fixture.flush()
        #expect(window.calls == ["content+frame"])
        #expect(window.frame == before)
    }

    @Test("Flyout-Wachstum nimmt die zuletzt gemessene Grösse, nicht fittingSize mitten im SwiftUI-Durchgang (dort 0)")
    func flyoutGrowsFromLastFitting() throws {
        let fixture = try HostFixture("panel \"d\" anchor=\"top\" { row { text \"a\" } }")
        let window = try #require(fixture.window("d"))
        let key = SurfaceHost.key("d", HostFixture.screen.key)
        let before = window.frame
        window.fittingSize = .zero
        window.calls = []
        try #require(fixture.host.context).onFlyoutExtent(key, EdgeInsets(top: 0, leading: 0, bottom: 200, trailing: 0))
        #expect(window.calls.first == "content+frame")
        #expect(window.frame.width == before.width)
        #expect(window.frame.height == before.height + 200)
        #expect(window.frame.maxY == before.maxY)
    }

    @Test("AppKit-Fenster: Polsterung und Rahmen in einem Schritt, Inhalt danach schon im neuen Rahmen ausgelegt")
    func contentAndFrameTogether() {
        let window = AppKitHostWindow(spec: SurfaceWindowSpec(kind: "panel", property: { _ in .null }), content: AnyView(EmptyView()), stage: StageRecorder())
        window.setFrame(CGRect(x: -40_000, y: -40_000, width: 100, height: 40), glide: false)
        let target = CGRect(x: -40_000, y: -40_000, width: 220, height: 40)
        window.setContent(AnyView(Color.red.padding(.trailing, 120)), frame: target, glide: false)
        #expect(window.window.frame == target)
        #expect(window.hosting.frame.size == target.size)
        #expect(!window.hosting.needsLayout)
        window.close()
    }
}
