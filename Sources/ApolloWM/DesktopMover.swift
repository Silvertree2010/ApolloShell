import AppKit
import ApplicationServices

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

    public static func send(_ window: AXWindow, toDesktop number: Int,
                            shortcut: DesktopShortcuts.Shortcut) async -> Result<Void, Failure> {
        let order = Spaces.ordered()
        guard order.indices.contains(number - 1) else { return .failure(.noSuchDesktop(number)) }
        guard Spaces.of(window.windowID) != order[number - 1] else { return .failure(.alreadyThere) }
        await waitForModifiersReleased()
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

    private static func waitForModifiersReleased() async {
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        for _ in 0..<80 {
            if CGEventSource.flagsState(.hidSystemState).intersection(modifiers).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    nonisolated static func titleBarSpot(of window: AXUIElement, pid: pid_t, frame: CGRect) -> CGPoint? {
        let system = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(system, 0.3)
        let rows: [CGFloat] = [6, 12, 20]
        let columns: [CGFloat] = [0.5, 0.4, 0.6, 0.3, 0.7, 0.2, 0.8]
        for dy in rows {
            for fraction in columns {
                let point = CGPoint(x: (frame.minX + frame.width * fraction).rounded(), y: frame.minY + dy)
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
