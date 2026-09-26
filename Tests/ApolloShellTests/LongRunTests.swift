import Testing
import AppKit
import SwiftUI
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime
import ApolloShellCore
@testable import ApolloShell

@MainActor
@Suite("Dauerbetrieb: Bildschirme, Reloads, Abbau", .serialized)
struct LongRunTests {
    static let a = ShellHarness.a
    static let b = ShellHarness.b

    @Test("Bildschirm mit Vollbild-App ab, Vollbild vorbei, Bildschirm wieder an: Leiste ist wieder sichtbar")
    func fullscreenScreenComesBack() async throws {
        let harness = try ShellHarness("panel \"bar\" anchor=\"left\" { row {} }")
        harness.screens = [Self.a.key: Self.a, Self.b.key: Self.b]
        try await harness.start()
        harness.fullscreenKeys = [Self.b.key]
        harness.shell.fullscreen.check()
        #expect(harness.window("bar", Self.b)?.isShown == false)
        harness.shell.screensDidChange([Self.a.key: Self.a])
        harness.fullscreenKeys = []
        harness.shell.fullscreen.check()
        harness.shell.screensDidChange([Self.a.key: Self.a, Self.b.key: Self.b])
        harness.shell.fullscreen.check()
        harness.settle()
        #expect(harness.runtime.surface("bar", screenKey: Self.b.key)?.isVisible == true)
        #expect(harness.window("bar", Self.b)?.isShown == true)
        harness.shell.shutdown()
    }

    static let busy = """
    var items type="list" {
        - "a"
        - "b"
        - "c"
    }
    var on #true
    panel "bar" anchor="left" {
        each item in="{var.items}" key="{item}" { text "{item} {var.on}" }
        when "{var.on}" { button { on-click { set "on" #false } } }
    }
    popup "menu" { row { text "{var.on}" } }
    """

    struct Counters: Equatable {
        var subscriptions: Int
        var bindings: Int
        var controllers: Int
        var surfaces: Int
    }

    func counters(_ harness: ShellHarness) -> Counters {
        let assembly = harness.shell.assembly!
        return Counters(subscriptions: assembly.store.subscriptionCount, bindings: assembly.bindings.liveBindingCount,
                        controllers: harness.shell.host.controllers.count, surfaces: harness.runtime.surfaceNodes.count)
    }

    @Test("20 Reloads und 20 Mal Bildschirm ab und an: Abos, Bindings und Fenster bleiben beim Ausgangswert")
    func countersStayFlat() async throws {
        let harness = try ShellHarness(Self.busy)
        harness.screens = [Self.a.key: Self.a, Self.b.key: Self.b]
        try await harness.start()
        harness.runtime.open("menu", screenKey: Self.a.key)
        harness.settle()
        let before = counters(harness)
        #expect(harness.shell.overlay.problems.filter { $0.severity != .note }.isEmpty)
        #expect(before.controllers == 4)
        for round in 0..<20 {
            try harness.write(Self.busy + (round % 2 == 0 ? "\npopup \"extra\" { row { text \"{var.on}\" } }" : ""))
            await harness.shell.reload()?.value
            harness.settle()
        }
        try harness.write(Self.busy)
        await harness.shell.reload()?.value
        harness.settle()
        for _ in 0..<20 {
            harness.shell.screensDidChange([Self.a.key: Self.a])
            harness.settle()
            harness.shell.screensDidChange([Self.a.key: Self.a, Self.b.key: Self.b])
            harness.settle()
        }
        let after = counters(harness)
        #expect(after.controllers == before.controllers)
        #expect(after.surfaces == before.surfaces)
        #expect(after.bindings == before.bindings)
        #expect(after.subscriptions == before.subscriptions)
        harness.shell.shutdown()
    }

    @Test("AppKit-Fenster wird nach close freigegeben, auch mit Schleier und Schliess-Auslösern")
    func hostWindowReleased() {
        weak var released: AppKitHostWindow?
        weak var panel: NSWindow?
        autoreleasepool {
            let stage = StageRecorder()
            var spec = SurfaceWindowSpec(kind: "popup", property: { _ in .null })
            spec.closeOn = [.outsideClick, .mouseLeave, .escape]
            let window = AppKitHostWindow(spec: spec, content: AnyView(Text("x")), stage: stage)
            window.onCloseRequest = {}
            window.show(focus: false)
            window.close()
            released = window
            panel = window.window
        }
        RunLoopPump.run(0.05)
        #expect(released == nil)
        #expect(panel == nil)
    }
}
