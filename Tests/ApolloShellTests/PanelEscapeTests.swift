import Testing
import AppKit
@testable import ApolloShell

@MainActor
@Suite("HostPanel: schlichtes Escape schliesst")
struct PanelEscapeTests {
    func mk() -> (HostPanel, () -> Int) {
        let p = HostPanel(level: .normal, behavior: [], takesKeyboard: true, mayLeaveScreen: false)
        p.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        var n = 0
        p.onEscape = { n += 1; return true }
        return (p, { n })
    }

    func ev(_ p: NSWindow, _ code: UInt16, _ m: NSEvent.ModifierFlags = [], _ c: String = "\u{1b}") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: m, timestamp: 0, windowNumber: p.windowNumber, context: nil, characters: c, charactersIgnoringModifiers: c, isARepeat: false, keyCode: code)!
    }

    @Test("Escape ohne Modifier ruft onEscape einmal")
    func plain() {
        let (p, n) = mk()
        p.sendEvent(ev(p, 53))
        #expect(n() == 1)
    }

    @Test("Escape mit Command wird nicht abgefangen")
    func command() {
        let (p, n) = mk()
        p.sendEvent(ev(p, 53, .command, ""))
        #expect(n() == 0)
    }

    @Test("andere Taste wird nicht abgefangen")
    func other() {
        let (p, n) = mk()
        p.sendEvent(ev(p, 0, [], "a"))
        #expect(n() == 0)
    }

    @Test("Escape bei markiertem Text im Textfeld wird nicht abgefangen")
    func marked() {
        let (p, n) = mk()
        let t = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 50))
        p.contentView?.addSubview(t)
        #expect(p.makeFirstResponder(t))
        t.setMarkedText("あ", selectedRange: NSRange(location: 0, length: 1), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(t.hasMarkedText())
        p.sendEvent(ev(p, 53, [], ""))
        #expect(n() == 0)
    }
}
