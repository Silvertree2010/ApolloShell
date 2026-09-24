import Testing
import AppKit
import SwiftUI
import ApolloBase
import ApolloConfig
import ApolloStyle
import ApolloRuntime
@testable import ApolloShell

@MainActor
final class StageRecorder: WindowStage {
    struct Fade: Equatable {
        var from: CGFloat
        var to: CGFloat
    }

    var visible: Set<ObjectIdentifier> = []
    var fronts: [(window: ObjectIdentifier, key: Bool, alpha: CGFloat)] = []
    var fades: [ObjectIdentifier: [Fade]] = [:]
    var glides: [CGRect] = []
    var pins = 0
    var glideInstantly = true
    var pending: [@MainActor () -> Void] = []

    func front(_ window: NSWindow, key: Bool) {
        visible.insert(ObjectIdentifier(window))
        fronts.append((ObjectIdentifier(window), key, window.alphaValue))
    }

    func out(_ window: NSWindow) { visible.remove(ObjectIdentifier(window)) }
    func isVisible(_ window: NSWindow) -> Bool { visible.contains(ObjectIdentifier(window)) }

    func fade(_ window: NSWindow, to alpha: CGFloat, duration: TimeInterval, curve: CAMediaTimingFunction, completion: @escaping @MainActor () -> Void) {
        fades[ObjectIdentifier(window), default: []].append(Fade(from: window.alphaValue, to: alpha))
        pending.append {
            window.alphaValue = alpha
            completion()
        }
    }

    var glideEnds: [@MainActor () -> Void] = []

    func glide(_ window: NSWindow, to frame: CGRect, duration: TimeInterval, curve: CAMediaTimingFunction, completion: @escaping @MainActor () -> Void) {
        glides.append(frame)
        glideEnds.append(completion)
        if glideInstantly { window.setFrame(frame, display: false) }
    }

    func pin(_ window: NSWindow) { pins += 1 }
    func activateApp() {}

    func finish() {
        let work = pending
        pending = []
        work.forEach { $0() }
    }
}

@MainActor
@Suite("Fix-Runde 1: AppKit-Fenster über die Bühne")
struct AppKitStageTests {
    func spec(_ kind: String, _ values: [String: Value] = [:]) -> SurfaceWindowSpec {
        SurfaceWindowSpec(kind: kind, property: { values[$0] ?? .null })
    }

    func geometry() -> MotionGeometry {
        MotionGeometry(edge: .top, size: CGSize(width: 200, height: 100), topInset: 0, flipped: false)
    }

    @Test("Befund 1: Einblenden beginnt unsichtbar (fade, slide, grow)")
    func fadeStartsHidden() {
        for motion in ["fade", "slide", "grow"] {
            let stage = StageRecorder()
            let window = AppKitHostWindow(spec: spec("popup", ["motion": .string(motion)]), content: AnyView(EmptyView()), stage: stage)
            window.setFrame(CGRect(x: 0, y: 0, width: 200, height: 100))
            window.animate(opening: true, focus: true, animator: AnimatorRegistry.builtin().animator(motion), geometry: geometry(), scrim: nil, screen: .zero) {}
            let fade = stage.fades[ObjectIdentifier(window.window)]?.last
            #expect(fade == StageRecorder.Fade(from: 0, to: 1), "\(motion)")
            #expect(stage.fronts.last?.alpha == 0, "\(motion)")
            stage.finish()
            #expect(window.window.alphaValue == 1)
        }
    }

    @Test("Befund 8: Fokus aus present wird durchgereicht")
    func focusPassesThrough() {
        let stage = StageRecorder()
        let window = AppKitHostWindow(spec: spec("popup"), content: AnyView(EmptyView()), stage: stage)
        window.animate(opening: true, focus: false, animator: FadeAnimator(), geometry: geometry(), scrim: nil, screen: .zero) {}
        #expect(stage.fronts.last?.key == false)
        window.hide()
        window.animate(opening: true, focus: true, animator: FadeAnimator(), geometry: geometry(), scrim: nil, screen: .zero) {}
        #expect(stage.fronts.last?.key == true)
    }

    @Test("Befund 5: keyboard, overhang, motion und sticky wirken auch nach dem Bau")
    func applyChangesPanel() throws {
        let stage = StageRecorder()
        let window = AppKitHostWindow(spec: spec("panel", ["sticky": .bool(false)]), content: AnyView(EmptyView()), stage: stage)
        let panel = try #require(window.window as? ShellPanel)
        #expect(!panel.canBecomeKey)
        #expect(!panel.mayLeaveScreen)
        window.show(focus: false)
        #expect(stage.pins == 0)
        window.apply(spec("panel", ["keyboard": .bool(true), "overhang": .bool(true), "sticky": .bool(true)]))
        #expect(panel.canBecomeKey)
        #expect(panel.mayLeaveScreen)
        #expect(stage.pins == 1)
        let popup = AppKitHostWindow(spec: spec("popup", ["motion": .string("none"), "keyboard": .bool(false)]), content: AnyView(EmptyView()), stage: stage)
        let popupPanel = try #require(popup.window as? ShellPanel)
        #expect(!popupPanel.mayLeaveScreen)
        popup.apply(spec("popup", ["motion": .string("slide")]))
        #expect(popupPanel.mayLeaveScreen)
        #expect(popupPanel.canBecomeKey)
    }

    @Test("Befund 6: Overlay misst nach dem Rendern und nimmt den ersten Klick")
    func overlaySize() throws {
        let stage = StageRecorder()
        let model = ErrorOverlayModel()
        model.schedule = { _, _ in }
        let overlay = ErrorOverlayWindow(model: model, open: { _ in }, reload: {}, stage: stage, visibleFrame: { CGRect(x: 0, y: 0, width: 1440, height: 870) })
        model.show([Diagnostic(.error, "one")])
        let small = try #require(overlay.panel).frame
        model.show((0..<8).map { Diagnostic(.error, "problem number \($0) with a longer message") })
        let large = try #require(overlay.panel).frame
        #expect(large.height > small.height)
        #expect(abs(large.maxY - (870 - 12)) < 1)
        #expect(overlay.hostingView?.acceptsFirstMouse(for: nil) == true)
        let sized = AppKitHostWindow(spec: SurfaceWindowSpec(kind: "popup", property: { _ in .null }), content: AnyView(Text("Hello there").padding(20)), stage: stage)
        #expect(sized.fittingSize.width > 40 && sized.fittingSize.height > 20)
    }
}

@MainActor
@Suite("Fix-Runde 1: Fenster-Host")
struct HostFixRoundOneTests {
    @Test("Befund 2: Ticker je Oberfläche, alter Ticker stoppt, nach dem Schliessen kein Rahmen mehr")
    func tickerLifecycle() throws {
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
        let first = try #require(tickers.first)
        #expect(first.tick?(0.05) == true)
        fixture.assembly.runtime.close("menu")
        #expect(tickers.count == 2)
        #expect(first.stops == 1)
        let second = tickers[1]
        #expect(second.tick?(0.05) == true)
        fixture.window("menu")?.finishAnimations()
        #expect(fixture.host.frames.frames[key] == nil)
        _ = second.tick?(0.2)
        #expect(fixture.host.frames.frames[key] == nil)
        #expect(second.stops == 1)
        fixture.assembly.runtime.open("menu", screenKey: nil)
        try fixture.reload("panel \"other\" { row {} }")
        #expect(tickers[2].stops == 1)
        token.cancel()
    }

    @Test("Befund 3: window behält den Rahmen des Users, min-width/min-height als Mindestgrösse")
    func windowKeepsUserFrame() throws {
        let css = "#settings { width: 400px; height: 300px; min-width: 320px; min-height: 200px; }"
        let fixture = try HostFixture("window \"settings\" title=\"Settings\" { row {} }", css: css)
        #expect(fixture.window("settings") == nil)
        fixture.assembly.runtime.open("settings", screenKey: nil)
        let window = try #require(fixture.window("settings"))
        #expect(window.frame.size == CGSize(width: 400, height: 300))
        #expect(window.minSize == CGSize(width: 320, height: 200))
        let moved = CGRect(x: 10, y: 20, width: 500, height: 420)
        window.frame = moved
        try fixture.reload("window \"settings\" title=\"Einstellungen\" { row {} }", css: css.replacingOccurrences(of: "400px", with: "420px"))
        fixture.host.resync()
        #expect(window.frame == moved)
        let saved = try HostFixture("window \"prefs\" autosave=\"prefs\" { row {} }", css: "#prefs { width: 400px; height: 300px; }")
        saved.factory.restorable = CGRect(x: 5, y: 5, width: 600, height: 500)
        saved.assembly.runtime.open("prefs", screenKey: nil)
        let prefs = try #require(saved.window("prefs"))
        #expect(prefs.frame == CGRect(x: 5, y: 5, width: 600, height: 500))
    }

    @Test("Befund 7: scrim wirkt auch bei motion=none")
    func scrimWithoutMotion() throws {
        let fixture = try HostFixture("popup \"dim\" motion=\"none\" scrim=0.4 { row {} }")
        fixture.assembly.runtime.open("dim", screenKey: nil)
        let window = try #require(fixture.window("dim"))
        #expect(window.animations.map(\.animator) == ["none"])
        fixture.assembly.runtime.close("dim")
        window.finishAnimations()
        #expect(!window.isShown)
        #expect(fixture.link.finished == ["dim"])
    }

    @Test("Befund 8: Fokus aus open erreicht das Fenster")
    func focusFromHost() throws {
        let fixture = try HostFixture("popup \"menu\" { row {} }")
        fixture.assembly.runtime.open("menu", screenKey: nil)
        #expect(fixture.window("menu")?.focuses == [true])
    }

    @Test("Befund 9: close-Wunsch und osd-Timer schliessen nur ihre Instanz")
    func closeOnlyThisInstance() throws {
        let fixture = try HostFixture("popup \"menu\" { row {} }\nosd \"volume\" timeout=\"1s\" { row {} }")
        let side = ScreenGeometry(key: "Side 1920x1080", frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), visible: CGRect(x: 1440, y: 0, width: 1920, height: 1050))
        fixture.host.screens[side.key] = side
        fixture.assembly.runtime.setScreens([HostFixture.screen.key, side.key])
        let runtime = fixture.assembly.runtime
        runtime.open("menu", screenKey: HostFixture.screen.key)
        let other = try #require(fixture.host.controllers[SurfaceHost.key("menu", side.key)]?.window)
        other.onCloseRequest?()
        #expect(runtime.surface("menu", screenKey: HostFixture.screen.key)?.isOpen == true)
        fixture.window("menu")?.onCloseRequest?()
        #expect(runtime.surface("menu", screenKey: HostFixture.screen.key)?.isOpen == false)
        var timers: [DispatchWorkItem] = []
        fixture.host.scheduleTimer = { _, work in timers.append(work) }
        fixture.host.pointer = { CGPoint(x: -500, y: -500) }
        runtime.open("volume", screenKey: side.key)
        runtime.open("volume", screenKey: HostFixture.screen.key)
        #expect(runtime.surface("volume", screenKey: side.key)?.isOpen == true)
        #expect(runtime.surface("volume", screenKey: HostFixture.screen.key)?.isOpen == true)
        timers.first?.perform()
        #expect(runtime.surface("volume", screenKey: side.key)?.isOpen == false)
        #expect(runtime.surface("volume", screenKey: HostFixture.screen.key)?.isOpen == true)
    }

    @Test("Befund 5: sticky aus ersetzt genau dieses Fenster, sticky an heftet ohne Neubau")
    func stickyChange() throws {
        let fixture = try HostFixture("panel \"bar\" { row {} }\npanel \"clock\" sticky=#false { row {} }")
        let bar = try #require(fixture.window("bar"))
        let clock = try #require(fixture.window("clock"))
        try fixture.reload("panel \"bar\" sticky=#false { row {} }\npanel \"clock\" { row {} }")
        #expect(bar.closed)
        #expect(fixture.window("bar") !== bar)
        #expect(fixture.window("clock") === clock)
        #expect(clock.spec.sticky)
        #expect(fixture.host.stats.windowsCreated == 3)
    }

    @Test("Befund 4: geänderter Offset gleitet, erster Rahmen springt")
    func offsetGlides() throws {
        let fixture = try HostFixture("var lift 0\npanel \"stack\" anchor=\"bottom-right\" offset-y=\"{var.lift}\" { row {} }", css: "#stack { width: 300px; height: 200px; }")
        let window = try #require(fixture.window("stack"))
        #expect(window.glides.isEmpty)
        let before = window.frame
        _ = fixture.assembly.vars.set("lift", .number(120))
        fixture.flush()
        #expect(window.glides.count == 1)
        #expect(window.frame.minY == before.minY + 120)
    }
}
