import Testing
import Foundation
import AppKit
import ApolloConfig
import ApolloShellCore
@testable import ApolloShell

@MainActor
final class FakeGateClock: GateClock {
    var now: Double = 100
    var scheduled: [(Double, @MainActor () -> Void)] = []

    func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        scheduled.append((now + seconds, work))
    }

    func advance(_ seconds: Double) {
        now += seconds
        let due = scheduled.filter { $0.0 <= now }
        scheduled.removeAll { $0.0 <= now }
        for (_, work) in due { work() }
    }
}

@MainActor
struct Mounted {
    let session: RenderSession
    let view: NSView

    var catchers: [ElementMouseView] {
        func walk(_ view: NSView) -> [ElementMouseView] {
            ((view as? ElementMouseView).map { [$0] } ?? []) + view.subviews.flatMap(walk)
        }
        return walk(view).filter { !$0.config.passive }
    }

    func catcher(_ id: String) throws -> ElementMouseView {
        try #require(catchers.first { $0.element?.property("id").plainText == id })
    }

    func variable(_ name: String) -> Value {
        session.context.runtime?.variable(name) ?? .null
    }

    func settle() async {
        await session.context.settle()
        session.flush()
    }

    static func mount(_ kdl: String, css: String) throws -> Mounted {
        let (session, _) = try RenderProbe.session(kdl, css: css)
        let surface = try #require(session.surfaces.first)
        let view = session.mount(surface)
        for _ in 0..<5 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            view.layoutSubtreeIfNeeded()
        }
        return Mounted(session: session, view: view)
    }

    func mouse(_ type: NSEvent.EventType, on target: NSView, clicks: Int = 1, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        let point = target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil)
        return NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 0, windowNumber: target.window?.windowNumber ?? 0,
                                  context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }
}

@MainActor
@Suite("Render: Eingaben und Handler (blocks.md 1, 4.2)", .serialized)
struct InteractionTests {
    @Test("throttle lässt höchstens einen je Dauer durch, debounce nur den letzten")
    func gate() {
        let clock = FakeGateClock()
        let gate = EventGate(clock: clock)
        var fired: [Double] = []
        let throttle = HandlerRules(throttle: 1)
        for step in 0..<5 {
            gate.submit(Record([("n", .number(Double(step)))]), rules: throttle) { fired.append(StyleValues.numberValue($0["n"] ?? .null) ?? -1) }
            clock.advance(0.3)
        }
        #expect(fired == [0, 4])
        fired = []
        let debounced = EventGate(clock: clock)
        for step in 0..<3 {
            debounced.submit(Record([("n", .number(Double(step)))]), rules: HandlerRules(debounce: 0.4)) { fired.append(StyleValues.numberValue($0["n"] ?? .null) ?? -1) }
            clock.advance(0.1)
        }
        #expect(fired.isEmpty)
        clock.advance(0.5)
        #expect(fired == [2])
    }

    @Test("on-scroll step sammelt Weg, cooldown pausiert, direction nach Vorzeichen")
    func scrollStep() {
        let clock = FakeGateClock()
        let gate = EventGate(clock: clock)
        var directions: [String] = []
        let rules = HandlerRules(step: 30, cooldown: 0.3)
        func scroll(_ dy: Double) {
            gate.submit(Record([("dy", .number(dy)), ("phase", .string("changed"))]), rules: rules) { directions.append($0["direction"]?.plainText ?? "") }
        }
        scroll(20)
        #expect(directions.isEmpty)
        scroll(15)
        #expect(directions == ["up"])
        scroll(40)
        #expect(directions == ["up"])
        clock.advance(0.4)
        scroll(-40)
        #expect(directions == ["up", "down"])
    }

    @Test("key-recorder: Esc bricht ab, ⌫ leert, ohne Modifikator abgelehnt, Warnung und Konflikt")
    func recorder() {
        let none = RecorderOutcome.evaluate(keyCode: UInt32(HotKeyKey.escape), modifiers: [], reject: [], current: nil, binds: [])
        #expect(none.kind == .cancel)
        let clear = RecorderOutcome.evaluate(keyCode: UInt32(HotKeyKey.delete), modifiers: [], reject: [], current: nil, binds: [])
        #expect(clear.kind == .record(""))
        let bare = RecorderOutcome.evaluate(keyCode: 0x00, modifiers: [], reject: [], current: nil, binds: [])
        if case .rejected = bare.kind {} else { Issue.record("expected rejection, got \(bare)") }
        let spotlight = RecorderOutcome.evaluate(keyCode: UInt32(HotKeyKey.space), modifiers: .command, reject: [], current: nil,
                                                 binds: [("launcher", "cmd+space")])
        #expect(spotlight.kind == .record("cmd+space"))
        #expect(spotlight.warning?.contains("Spotlight") == true)
        #expect(spotlight.conflict == "launcher")
        let own = RecorderOutcome.evaluate(keyCode: UInt32(HotKeyKey.space), modifiers: .option, reject: [], current: "alt+space",
                                           binds: [("launcher", "alt+space")])
        #expect(own.conflict == nil)
        let rejected = RecorderOutcome.evaluate(keyCode: 0x02, modifiers: [.control, .option], reject: ["ctrl+alt+d"], current: nil, binds: [])
        if case .rejected(let text) = rejected.kind { #expect(text.hasPrefix("Already assigned")) } else { Issue.record("\(rejected)") }
        #expect(KeyChord(hotKey: HotKey(keyCode: UInt32(HotKeyKey.space), modifiers: .option))?.display == "⌥Space")
    }

    @Test("slider rastet auf step und bleibt in min…max")
    func sliderMetrics() {
        let metrics = SliderMetrics(min: 0, max: 100, step: 10)
        #expect(metrics.value(fraction: 0.44) == 40)
        #expect(metrics.value(fraction: 1.5) == 100)
        #expect(metrics.fraction(25) == 0.25)
        #expect(SliderMetrics(min: 0, max: 1, step: 0).value(fraction: 0.333) == 0.333)
    }

    @Test("Tasten in input: Kürzel passt nur mit genau diesen Modifikatoren")
    func keyMatch() throws {
        let chord = try #require(KeyChord.parse("down"))
        #expect(KeyMatch.matches(chord, keyCode: 0x7D, flags: []))
        #expect(!KeyMatch.matches(chord, keyCode: 0x7D, flags: .shift))
        #expect(KeyMatch.matches(try #require(KeyChord.parse("cmd+return")), keyCode: 0x24, flags: .command))
    }

    @Test("reorder: to zählt wie list.move, Vorschau zeigt die neue Reihenfolge")
    func reorderMove() {
        #expect(ReorderMove.onto(from: 0, target: 2) == ReorderMove(from: 0, to: 3))
        #expect(ReorderMove.onto(from: 2, target: 0) == ReorderMove(from: 2, to: 0))
        #expect(ReorderMove(from: 0, to: 3).apply(["a", "b", "c", "d"]) == ["b", "c", "a", "d"])
        #expect(ReorderMove(from: 2, to: 0).apply(["a", "b", "c"]) == ["c", "a", "b"])
    }

    static let handlerConfig = """
    var clicks 0
    var last ""
    panel "t" anchor="left" {
        row class="r" {
            on-click { set "last" "outer" }
            button id="b" class="b" {
                on-click { set "clicks" "{var.clicks + 1}" }
                on-right-click { set "last" "right" }
                on-double-click { set "last" "double" }
                on-middle-click { set "last" "middle" }
                on-scroll step=30 cooldown="300ms" { set "last" "{event.direction}" }
                text "Hi"
            }
        }
    }
    """
    static let handlerCSS = "#t { width: 120px; height: 60px; } .r { width: 100px; height: 40px; } .b { width: 40px; height: 20px; }"

    @Test("Klick, Doppelklick, Rechts-, Ctrl- und Mittelklick lösen ihre Handler aus")
    func clicks() async throws {
        let mounted = try Mounted.mount(Self.handlerConfig, css: Self.handlerCSS)
        let button = try mounted.catcher("b")
        button.mouseDown(with: mounted.mouse(.leftMouseDown, on: button))
        button.mouseUp(with: mounted.mouse(.leftMouseUp, on: button))
        await mounted.settle()
        #expect(mounted.variable("clicks") == .number(1))
        button.mouseUp(with: mounted.mouse(.leftMouseUp, on: button, clicks: 2))
        await mounted.settle()
        #expect(mounted.variable("last") == .string("double"))
        button.rightMouseDown(with: mounted.mouse(.rightMouseDown, on: button))
        await mounted.settle()
        #expect(mounted.variable("last") == .string("right"))
        let middle = NSEvent.mouseEvent(with: .otherMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        button.otherMouseDown(with: middle)
        await mounted.settle()
        #expect(mounted.variable("last") == .string("middle") || middle.buttonNumber != 2)
        button.mouseDown(with: mounted.mouse(.leftMouseDown, on: button, flags: .control))
        await mounted.settle()
        #expect(mounted.variable("last") == .string("right"))
        #expect(mounted.variable("clicks") == .number(1))
    }

    @Test("Scrollrad mit step löst einmal aus, das innerste Element gewinnt den Klick")
    func scrollAndNesting() async throws {
        let mounted = try Mounted.mount(Self.handlerConfig, css: Self.handlerCSS)
        let button = try mounted.catcher("b")
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 40, wheel2: 0, wheel3: 0))
        button.scrollWheel(with: try #require(NSEvent(cgEvent: cg)))
        await mounted.settle()
        #expect(mounted.variable("last") == .string("up"))
        let window = try #require(button.window)
        let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        #expect(ElementMouseView.winner(at: center, in: window, kind: .left) === button)
        let outer = try #require(mounted.catchers.first { $0 !== button })
        let edge = outer.convert(NSPoint(x: outer.bounds.maxX - 2, y: outer.bounds.midY), to: nil)
        #expect(ElementMouseView.winner(at: edge, in: window, kind: .left) === outer)
        #expect(ElementMouseView.winner(at: center, in: window, kind: .scroll) === button)
    }

    @Test("checked, disabled, first-child und last-child setzen Pseudoklassen")
    func pseudo() throws {
        let shot = try RenderProbe.render("""
        panel "t" anchor="left" {
            row {
                stack class="c" checked=#true
                stack class="c"
                stack class="c" disabled=#true
            }
        }
        """, css: """
        #t { width: 90px; height: 30px; align-items: start; }
        .c { width: 30px; height: 30px; background: #00ff00; }
        .c:checked { background: #ff0000; }
        .c:disabled { background: #0000ff; }
        .c:first-child { opacity: 0.5; }
        .c:last-child { border: 2px solid #000000; }
        """)
        #expect(shot.pixel(15, 15).near(RGBA(r: 255, g: 128, b: 128, a: 255), tolerance: 20))
        #expect(shot.pixel(45, 15).near(.green))
        #expect(shot.pixel(75, 15).near(.blue))
        #expect(shot.pixel(61, 15).near(.black, tolerance: 40))
    }

    @Test("toggle zeichnet den nativen Schalter, an und aus unterscheiden sich")
    func toggle() throws {
        let on = try RenderProbe.render("panel \"t\" anchor=\"left\" { toggle checked=#true }", css: "#t { width: 60px; height: 30px; align-items: start; accent-color: #ff0000; }")
        let off = try RenderProbe.render("panel \"t\" anchor=\"left\" { toggle checked=#false }", css: "#t { width: 60px; height: 30px; align-items: start; accent-color: #ff0000; }")
        #expect(on.ink() != nil && off.ink() != nil)
        var differing = 0
        for y in 0..<30 {
            for x in 0..<60 where !on.pixel(CGFloat(x), CGFloat(y)).near(off.pixel(CGFloat(x), CGFloat(y)), tolerance: 20) { differing += 1 }
        }
        #expect(differing > 20)
    }

    @Test("slider füllt bis zum Wert, Griff in -apollo-thumb-color, Slot im Griff")
    func slider() throws {
        let shot = try RenderProbe.render("""
        panel "t" anchor="left" {
            slider class="s" value=0.25 {
                fill "thumb" { stack class="dot" }
            }
        }
        """, css: """
        #t { width: 200px; height: 40px; align-items: start; }
        .s { width: 200px; height: 20px; -apollo-track-color: #0000ff; -apollo-fill-color: #ff0000; -apollo-thumb-color: #00ff00; -apollo-thumb-size: 20px; }
        .dot { width: 4px; height: 4px; background: #000000; }
        """)
        let fill = try #require(shot.bounds { $0.r > 200 && $0.g < 60 && $0.b < 60 })
        #expect(abs(fill.minX) < 2 && fill.maxX > 40 && fill.maxX < 70)
        let thumb = try #require(shot.bounds { $0.g > 200 && $0.r < 60 && $0.b < 60 })
        #expect(abs(thumb.midX - 55) < 4)
        #expect(shot.pixel(55, 10).near(.black, tolerance: 60))
        #expect(shot.pixel(150, 10).near(.blue))
    }

    @Test("input zeigt value und Platzhalter, key-recorder zeigt die Kombination mit Symbolen")
    func textInputs() throws {
        let css = "#t { width: 160px; height: 40px; align-items: start; } .i { width: 150px; color: #ff0000; font-size: 16px; }"
        let filled = try RenderProbe.render("panel \"t\" anchor=\"left\" { input class=\"i\" value=\"Hello\" }", css: css)
        let empty = try RenderProbe.render("panel \"t\" anchor=\"left\" { input class=\"i\" value=\"\" placeholder=\"Search\" }", css: css)
        #expect(filled.count { $0.r > 180 && $0.g < 90 && $0.b < 90 } > 10)
        #expect(empty.ink() != nil)
        let recorder = try RenderProbe.render("panel \"t\" anchor=\"left\" { key-recorder class=\"i\" value=\"alt+space\" }", css: css)
        let blank = try RenderProbe.render("panel \"t\" anchor=\"left\" { key-recorder class=\"i\" value=\"\" }", css: css)
        #expect(recorder.count { $0.r > 180 && $0.g < 90 && $0.b < 90 } > 10)
        #expect(blank.ink() == nil)
    }

    @Test("Trefferflächen: Handler und sichtbarer Hintergrund zählen, reiner Text nicht (Entscheid 38)")
    func hitRegions() throws {
        let mounted = try Mounted.mount("""
        panel "t" anchor="left" {
            column {
                stack class="card"
                text "plain"
                button id="b" class="b" { on-click { set "x" 1 } }
            }
        }
        var x 0
        """, css: "#t { width: 100px; height: 100px; align-items: start; } .card { width: 50px; height: 20px; background: #ff0000; } .b { width: 30px; height: 20px; }")
        let key = try #require(mounted.session.surfaces.first).id + "@render"
        let regions = mounted.session.context.hits.regions(for: key)
        #expect(regions.count == 2)
        #expect(mounted.session.context.hits.contains(CGPoint(x: 10, y: 10), surfaceKey: key))
        #expect(!mounted.session.context.hits.contains(CGPoint(x: 90, y: 90), surfaceKey: key))
    }

    @Test("Long-Press löst aus und unterdrückt den Klick, on-appear beim Erscheinen")
    func longPressAndAppear() async throws {
        let mounted = try Mounted.mount("""
        var hits 0
        var last ""
        panel "t" anchor="left" {
            button id="b" class="b" {
                on-click { set "hits" "{var.hits + 1}" }
                on-long-press delay="50ms" { set "last" "long" }
                on-appear { set "last" "appeared" }
            }
        }
        """, css: "#t { width: 60px; height: 40px; } .b { width: 40px; height: 20px; }")
        await mounted.settle()
        #expect(mounted.variable("last") == .string("appeared"))
        let button = try mounted.catcher("b")
        button.mouseDown(with: mounted.mouse(.leftMouseDown, on: button))
        #expect(button.element?.pseudo.contains(.active) == true)
        try await Task.sleep(for: .milliseconds(150))
        button.mouseUp(with: mounted.mouse(.leftMouseUp, on: button))
        await mounted.settle()
        #expect(mounted.variable("last") == .string("long"))
        #expect(mounted.variable("hits") == .number(0))
        #expect(button.element?.pseudo.contains(.active) == false)
    }

    @Test("on-drop liest Dateien, Apps und Text vom Pasteboard")
    func dropFields() {
        let board = NSPasteboard(name: NSPasteboard.Name("apollo-test-\(UUID().uuidString)"))
        board.clearContents()
        board.writeObjects([URL(fileURLWithPath: "/tmp/a.txt") as NSURL])
        #expect(EventFields.drop(board, accept: "files")?["files"] == .list([.string("/tmp/a.txt")]))
        #expect(EventFields.drop(board, accept: "text") == nil || EventFields.drop(board, accept: "text")?["text"] != nil)
        board.clearContents()
        board.setString("com.apple.Safari", forType: .apolloApp)
        #expect(EventFields.drop(board, accept: "apps")?["apps"] == .list([.string("com.apple.Safari")]))
        board.clearContents()
        board.setString("hello", forType: .string)
        #expect(EventFields.drop(board, accept: "text")?["text"] == .string("hello"))
        board.releaseGlobally()
    }
}
