import Testing
import AppKit
import SwiftUI
import ApolloBase
import ApolloConfig
import ApolloRuntime
import ApolloShellCore
@testable import ApolloShell

@MainActor
@Suite("Fix-Runde 2")
struct FixRoundTwoTests {
    @Test("Befund 11: willTerminate ruft shutdown synchron")
    func willTerminateRunsShutdownNow() async throws {
        let harness = try ShellHarness("popup \"menu\" { row {} }")
        try await harness.start()
        let center = NotificationCenter()
        harness.shell.installTermination(signals: [], center: center)
        center.post(name: NSApplication.willTerminateNotification, object: nil)
        #expect(harness.shell.shutdowns == 1)
        harness.shell.shutdown()
    }

    @Test("N6: Signal bei hängendem Main Thread beendet über den Rückfall-Timer")
    func signalFallbackExits() async throws {
        let exits = LockedList()
        let called = LockedList()
        let watch = TerminationWatch(signals: [SIGUSR1], queue: DispatchQueue(label: "termination-fallback"), center: NotificationCenter(), fallback: 0.1, hop: { _ in }, exitProcess: { exits.append($0) }) { number in
            called.append(number ?? 0)
        }
        kill(getpid(), SIGUSR1)
        for _ in 0..<200 where exits.values.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        watch.cancel()
        signal(SIGUSR1, SIG_DFL)
        #expect(exits.values == [0])
        #expect(called.values.isEmpty)
    }

    @Test("N1: Änderungen ausserhalb der Config-Ordner lösen keinen Reload aus")
    func unrelatedChangesIgnored() async throws {
        let harness = try ShellHarness("popup \"menu\" { row {} }")
        try await harness.start()
        let before = harness.shell.debouncer.pokes
        harness.shell.filesChanged([harness.home.appendingPathComponent("Library/Caches/x.db").path, "/private/tmp/other.txt"])
        #expect(harness.shell.debouncer.pokes == before)
        harness.shell.filesChanged([harness.config.appendingPathComponent("shell.kdl").path])
        #expect(harness.shell.debouncer.pokes == before + 1)
        harness.shell.shutdown()
    }

    @Test("N2: kein Ausblenden der App, ShellPanel lässt sich nicht ausblenden")
    func noHide() {
        let items = WindowMainMenu.make().items.flatMap { $0.submenu?.items ?? [] }
        #expect(!items.contains { $0.action == #selector(NSApplication.hide(_:)) })
        #expect(ShellPanel(level: .normal, behavior: []).canHide == false)
    }

    @Test("N3: Ticker läuft beim Öffnen bis zum Ende der Feder, nicht nur bis zum Einblenden")
    func tickerRunsFullSpring() throws {
        let fixture = try HostFixture("popup \"menu\" anchor=\"top\" motion=\"grow\" { row {} }")
        var tickers: [ManualTicker] = []
        fixture.host.makeTicker = { _ in
            let ticker = ManualTicker()
            tickers.append(ticker)
            return ticker
        }
        let token = fixture.host.frames.observe { _, _ in }
        let key = SurfaceHost.key("menu", HostFixture.screen.key)
        fixture.assembly.runtime.open("menu", screenKey: nil)
        let ticker = try #require(tickers.first)
        fixture.window("menu")?.finishAnimations()
        #expect(ticker.stops == 0)
        let total = fixture.host.animators.animator("grow").duration(opening: true)
        #expect(ticker.tick?(total / 2) == true)
        #expect(ticker.tick?(total + 0.01) == false)
        #expect(fixture.host.frames.frames[key] != nil)
        token.cancel()
    }

    @Test("N4: gleiche Warnung einmal im Overlay, Notizen nicht")
    func warningsDeduplicated() async throws {
        let harness = try ShellHarness("popup \"menu\" { row {} }")
        try await harness.start()
        let providers = try #require(harness.shell.assembly?.providers)
        let before = harness.shell.overlay.problems.count
        providers.onWarning?(Diagnostic(.warning, "battery provider failed"))
        providers.onWarning?(Diagnostic(.warning, "battery provider failed"))
        providers.onWarning?(Diagnostic(.note, "just a note"))
        #expect(harness.shell.overlay.problems.count == before + 1)
        harness.shell.shutdown()
    }

    @Test("N5: gleiches Ziel während des Gleitens setzt nicht hart")
    func glideKeepsTarget() {
        let stage = StageRecorder()
        stage.glideInstantly = false
        let window = AppKitHostWindow(spec: SurfaceWindowSpec(kind: "panel", property: { _ in .null }), content: AnyView(EmptyView()), stage: stage)
        let start = CGRect(x: 0, y: 0, width: 200, height: 100)
        let target = CGRect(x: 0, y: 120, width: 200, height: 100)
        window.setFrame(start, glide: false)
        window.show(focus: false)
        window.setFrame(target, glide: true)
        window.setFrame(target, glide: false)
        window.setFrame(target, glide: true)
        #expect(stage.glides == [target])
        #expect(window.window.frame == start)
    }

    @Test("N7: ohne lesbaren Tastenzustand gilt nur das Loslassen")
    func repeatWithoutKeyState() throws {
        var scheduled: [@MainActor () -> Void] = []
        let repeater = KeyRepeater(timing: { .init(delay: 0.3, interval: 0.05) }, schedule: { _, work in
            scheduled.append(work)
            return DispatchWorkItem {}
        })
        let keys = try KeysFixture("""
        popup "menu" { row {} }
        bind "ctrl+alt+up" id="louder" repeat=#true { toggle "menu" }
        """, repeater: repeater)
        keys.keys.keyIsDown = { _ in false }
        keys.keys.keyStateReadable = { false }
        keys.registrar.press("ctrl+alt+up")
        scheduled.removeFirst()()
        try #require(scheduled.count == 1)
        scheduled.removeFirst()()
        #expect(keys.triggered.count == 3)
        #expect(!repeater.active.isEmpty)
    }

    @Test("Toast mit fullscreen=\"hide\" verschwindet im Vollbild, der Stapel läuft weiter")
    func toastHidesInFullscreen() async throws {
        let harness = try ShellHarness("toast \"default\" fullscreen=\"hide\" { row { text \"{toast.title}\" } }")
        let clock = ToastClock()
        clock.install(harness.shell.toasts)
        try await harness.start()
        _ = try await harness.shell.runActions("notify title=\"A\"")
        harness.settle()
        let surface = try #require(harness.runtime.surface("default", screenKey: ShellHarness.a.key))
        #expect(surface.isVisible)
        harness.runtime.setHiddenByFullscreen(true, screenKey: ShellHarness.a.key)
        #expect(!surface.isVisible)
        #expect(surface.isOpen)
        harness.runtime.setHiddenByFullscreen(false, screenKey: ShellHarness.a.key)
        #expect(surface.isVisible)
        harness.shell.shutdown()
    }
}
