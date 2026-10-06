import Testing
import Foundation
import AppKit
import SwiftUI
import ApolloBase
import ApolloConfig
import ApolloRuntime
@testable import ApolloShell

@MainActor
@Suite("Runde 4: Interaktion", .serialized)
struct InteractionRoundFourTests {
    @Test("tiling-tabs: zwei Tab-Leisten nebeneinander liegen je an ihrer eigenen Stelle")
    func tabBarsSideBySide() throws {
        let url = PackageResources.root.appendingPathComponent("Resources/configs/apolloshell-default/examples/tiling-tabs.kdl")
        let example = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: " | where 'screen' screen.id", with: "")
        let fixture = """
        fixture {
            wm {
                tab-bars {
                    - x=100 y=50 width=200 height=20 screen="render" active=1 {
                        tabs { - window=1 title="" app="A" }
                    }
                    - x=400 y=50 width=200 height=20 screen="render" active=2 {
                        tabs { - window=2 title="" app="B" }
                    }
                }
            }
        }
        """
        let shot = try RenderProbe.render(example, css: "#wm-tab-bars { width: 800px; height: 200px; } .wm-tab-bar { background: #ff0000; }", fixture: fixture)
        #expect(shot.bounds { $0.near(.red) } == CGRect(x: 100, y: 50, width: 500, height: 20))
        #expect(shot.pixel(100, 50).near(.red))
        #expect(shot.pixel(599, 69).near(.red))
        #expect(!shot.pixel(350, 55).near(.red))
    }

    func keyDown(_ keyCode: UInt16, window: Int) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window, context: nil,
                         characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}", isARepeat: false, keyCode: keyCode)!
    }

    @Test("input: key-Handler greift nur für Tasten im eigenen Fenster, nicht für ein anderes Fenster der App")
    func inputKeysStayInOwnWindow() async throws {
        let (session, _) = try RenderProbe.session("""
        var q ""
        var hits 0
        panel "t" anchor="left" {
            input bind="var.q" focus=#true {
                key "down" { set "hits" "{var.hits + 1}" }
            }
        }
        """, css: "#t { width: 120px; height: 30px; }")
        let surface = try #require(session.surfaces.first)
        let own = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 120, height: 30), styleMask: [.titled], backing: .buffered, defer: false)
        own.isReleasedWhenClosed = false
        defer { own.close() }
        let hosting = NSHostingView(rootView: session.root(surface, reserve: EdgeInsets()))
        own.contentView = hosting
        let mounted = Mounted(session: session, view: hosting)
        mounted.pump(10)
        let other = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 50, height: 50), styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close() }
        NSApp.sendEvent(keyDown(125, window: other.windowNumber))
        mounted.pump(3)
        await mounted.settle()
        #expect(mounted.variable("hits") == .number(0))
        NSApp.sendEvent(keyDown(125, window: own.windowNumber))
        mounted.pump(3)
        await mounted.settle()
        #expect(mounted.variable("hits") == .number(1))
    }

    func press(_ chord: String, surface id: String, in session: RenderSession) async throws {
        let surface = try #require(session.surface(id))
        let canonical = try #require(KeyNameTable.canonical(chord))
        for (index, handler) in surface.ir.keyHandlers.enumerated() where KeyNameTable.canonical(handler.chord) == canonical {
            _ = session.assembly.actions.trigger(handler.actions, site: "\(id)@\(surface.screenKey)#key#\(index)",
                                                 environment: ActionEnvironment(scope: LocalScope(), surfaceID: id, screenKey: surface.screenKey, event: Record([("chord", .string(canonical))])))
        }
        await session.context.settle()
        session.flush()
    }

    @Test("session: ↑ vom ersten Eintrag springt zum letzten, ↓ vom letzten zum ersten")
    func sessionArrowsFromNothing() async throws {
        let url = PackageResources.root.appendingPathComponent("Resources/configs/apolloshell-default/session.kdl")
        let (session, _) = try RenderProbe.session(try String(contentsOf: url, encoding: .utf8))
        let vars = session.assembly.actions.vars
        #expect(vars.value("ssel") == .string("lock"))
        try await press("up", surface: "sess", in: session)
        #expect(vars.value("ssel") == .string("shutdown"))
        try await press("up", surface: "sess", in: session)
        #expect(vars.value("ssel") == .string("restart"))
        vars.set("ssel", .string("shutdown"))
        try await press("down", surface: "sess", in: session)
        #expect(vars.value("ssel") == .string("lock"))
    }

    func click(window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 5, y: 5), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    @Test("flyout: Klick in ein anderes Fenster der Shell schliesst, Klick in die eigene Oberfläche nicht")
    func flyoutClosesOnClickInOtherShellWindow() async throws {
        let (session, _) = try RenderProbe.session(FlyoutTests.config, css: FlyoutTests.css)
        let surface = try #require(session.surfaces.first)
        let own = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        own.isReleasedWhenClosed = false
        defer { own.close() }
        let hosting = NSHostingView(rootView: AnyView(SurfaceView(surface: surface, context: session.context)))
        own.contentView = hosting
        let mounted = Mounted(session: session, view: hosting)
        mounted.pump(10)
        let other = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 50, height: 50), styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close() }
        NSApp.sendEvent(click(window: own))
        mounted.pump(3)
        await mounted.settle()
        #expect(mounted.variable("open") == .bool(true))
        NSApp.sendEvent(click(window: other))
        mounted.pump(3)
        await mounted.settle()
        #expect(mounted.variable("open") == .bool(false))
    }
}
