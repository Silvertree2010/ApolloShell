import Testing
import Foundation
import AppKit
import SwiftUI
import ApolloBase
import ApolloRuntime
@testable import ApolloShell

@MainActor
@Suite("Knopf: Tastaturfokus", .serialized)
struct ButtonFocusTests {
    func mount(_ config: String) throws -> (Mounted, NSWindow) {
        let (session, _) = try RenderProbe.session(config, css: "#t { width: 120px; height: 40px; } .b { width: 40px; height: 30px; } .b:focus { background: #ff0000; }")
        let surface = try #require(session.surfaces.first)
        let win = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 120, height: 40), styleMask: [.titled], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: session.root(surface, reserve: EdgeInsets()))
        win.contentView = hosting
        win.makeKeyAndOrderFront(nil)
        let mounted = Mounted(session: session, view: hosting)
        mounted.pump(10)
        return (mounted, win)
    }

    func key(_ code: UInt16, _ chars: String, window: Int) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    }

    @Test("Knopf mit on-click nimmt Fokus nur über die Tastaturnavigation von macOS, setzt dann :focus, und Leertaste löst on-click aus")
    func focusAndSpace() async throws {
        let (m, win) = try mount("""
        var hits 0
        panel "t" anchor="left" {
            button id="b1" class="b" { on-click { set "hits" "{var.hits + 1}" } }
        }
        """)
        defer { win.close() }
        let el = try #require(m.catchers.first?.element)
        win.selectKeyView(following: m.view)
        m.pump(10)
        guard NSApplication.shared.isFullKeyboardAccessEnabled else {
            #expect(!el.pseudo.contains(.focus))
            return
        }
        #expect(el.pseudo.contains(.focus))
        win.sendEvent(key(49, " ", window: win.windowNumber))
        m.pump(3)
        await m.settle()
        #expect(m.variable("hits") == .number(1))
    }

    @Test("Knopf ohne on-click ist nicht fokussierbar")
    func inertButton() throws {
        let (m, win) = try mount("""
        panel "t" anchor="left" {
            button id="b1" class="b" { }
        }
        """)
        defer { win.close() }
        win.selectKeyView(following: m.view)
        m.pump(10)
        #expect(m.catchers.isEmpty)
    }
}
