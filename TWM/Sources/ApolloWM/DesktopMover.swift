import AppKit
import ApplicationServices

/// Sends a window to another macOS desktop without turning System Integrity
/// Protection off. The only way left is the one a user has: hold the window
/// by its title bar and switch desktops, and macOS carries it along. So the
/// mover presses the mouse on a free spot of the title bar, nudges it,
/// switches with Apple's "Switch to Desktop N" shortcut (see
/// DesktopShortcuts), lets go and puts the pointer back.
///
/// It waits until no modifier key is held any more: a Super key still down
/// would turn the synthetic click into a control-click (a context menu) or
/// into the engine's own Super-drag.
@MainActor
public enum DesktopMover {
    public enum Failure: Error, CustomStringConvertible {
        case noSuchDesktop(Int)
        case alreadyThere
        case noFreeTitleBarSpot
        case windowGone

        public var description: String {
            switch self {
            case .noSuchDesktop(let number): "there is no desktop \(number)"
            case .alreadyThere: "the window is on that desktop already"
            case .noFreeTitleBarSpot: "no free spot on the title bar to hold the window by"
            case .windowGone: "the window is gone"
            }
        }
    }

    /// Carries `window` to desktop `number` (1-based, Mission Control order)
    /// and shows that desktop. `shortcut` is Apple's switch shortcut for it.
    public static func send(_ window: AXWindow, toDesktop number: Int,
                            shortcut: DesktopShortcuts.Shortcut) async -> Result<Void, Failure> {
        let order = Spaces.ordered()
        guard order.indices.contains(number - 1) else { return .failure(.noSuchDesktop(number)) }
        guard Spaces.of(window.windowID) != order[number - 1] else { return .failure(.alreadyThere) }
        await waitForModifiersReleased()
        // The window must be on screen to be held: wait for its desktop to
        // show if macOS is still switching there (a restored scratchpad).
        for _ in 0..<60 where Spaces.current() != Spaces.of(window.windowID) {
            try? await Task.sleep(for: .milliseconds(25))
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard let frame = window.serverFrame else { return .failure(.windowGone) }
        let element = window.element
        let pid = window.pid
        let grab = await Task.detached(priority: .userInitiated) {
            titleBarSpot(of: element, pid: pid, frame: frame)
        }.value
        guard let grab else { return .failure(.noFreeTitleBarSpot) }

        let pointer = CGEvent(source: nil)?.location ?? grab
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ type: CGEventType, at point: CGPoint) {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
        post(.mouseMoved, at: grab)
        try? await Task.sleep(for: .milliseconds(30))
        post(.leftMouseDown, at: grab)
        try? await Task.sleep(for: .milliseconds(40))
        // A small move, so macOS treats it as a window drag.
        for step in 1...3 {
            post(.leftMouseDragged, at: CGPoint(x: grab.x + CGFloat(step), y: grab.y))
            try? await Task.sleep(for: .milliseconds(15))
        }
        let held = CGPoint(x: grab.x + 3, y: grab.y)
        for keyDown in [true, false] {
            let key = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: keyDown)
            key?.flags = shortcut.flags
            key?.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(20))
        }
        // Keep holding while macOS slides to the other desktop.
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(25))
            post(.leftMouseDragged, at: held)
            if Spaces.current() == order[number - 1] { break }
        }
        try? await Task.sleep(for: .milliseconds(150))
        post(.leftMouseUp, at: held)
        try? await Task.sleep(for: .milliseconds(30))
        CGWarpMouseCursorPosition(pointer)
        return Spaces.of(window.windowID) == order[number - 1] ? .success(()) : .failure(.windowGone)
    }

    /// Waits (at most 2 s) until the user let go of every modifier key.
    private static func waitForModifiersReleased() async {
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        for _ in 0..<80 {
            if CGEventSource.flagsState(.hidSystemState).intersection(modifiers).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    /// A point on the window's title bar that holds nothing clickable: the
    /// system's hit test there must give the window itself (or an empty
    /// toolbar). Tries the middle first, then further out. Nil when there is
    /// none, e.g. a window without a title bar.
    nonisolated static func titleBarSpot(of window: AXUIElement, pid: pid_t, frame: CGRect) -> CGPoint? {
        // The app's own element, not the system-wide one: a system-wide hit
        // test can land in our own process and trap off the main thread.
        let system = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(system, 0.3)
        let rows: [CGFloat] = [6, 12, 20]
        let columns: [CGFloat] = [0.5, 0.4, 0.6, 0.3, 0.7, 0.2, 0.8]
        for dy in rows {
            for fraction in columns {
                let point = CGPoint(x: (frame.minX + frame.width * fraction).rounded(), y: frame.minY + dy)
                // Our own window there (a tab bar) is not the title bar.
                if WindowFocus.isOwnWindowOnTop(at: point) { continue }
                var hit: AXUIElement?
                guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
                      let hit else { continue }
                var hitPID: pid_t = 0
                AXUIElementGetPid(hit, &hitPID)
                guard hitPID == pid else { continue }
                let role = hit.string(kAXRoleAttribute)
                if role == kAXWindowRole, CFEqual(hit, window) { return point }
                if role == kAXToolbarRole { return point }
            }
        }
        return nil
    }
}
