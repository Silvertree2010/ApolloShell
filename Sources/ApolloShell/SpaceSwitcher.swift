import AppKit
import CoreGraphics

/// Switches desktops like ⌃← / ⌃→ (Mission Control "Move left/right a space",
/// on by default - measured 14.09. in com.apple.symbolichotkeys 79/81).
/// com.apple.symbolichotkeys 79/81).
/// macOS has no public interface for that; the private one
/// (CGSManagedDisplaySetCurrentSpace) only switches the display, not the
/// windows. The key press is exactly what Mission Control expects: ⌃ plus an
/// arrow, with the Fn flag real arrow keys carry (the key binding stands there
/// as 0x840000 = ⌃ | Fn). Posting key presses needs the accessibility
/// permission, which the launcher has. Karabiner does not see them (it sits in
/// front of the system, not behind it).
///
///
/// The dots only count desktops. When full-screen spaces lie in between, ⌃→
/// counts them in and a jump lands short - then click again.
@MainActor
enum SpaceSwitcher {
    private static let left: CGKeyCode = 123
    private static let right: CGKeyCode = 124
    /// The gap between several steps: every one starts its own swipe
    /// animation; too close together and macOS swallows some.
    private static let stepDelay: TimeInterval = 0.12

    /// `delta` desktops further (negative = to the left).
    static func step(_ delta: Int) {
        guard delta != 0, AXIsProcessTrusted() else { return }
        let key = delta > 0 ? right : left
        for index in 0..<abs(delta) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * stepDelay) {
                post(key)
            }
        }
    }

    /// "Show All Windows" out of Apple's Dock menu: App Exposé, so ⌃↓
    /// (Mission Control "Application windows", on by default - symbolichotkeys
    /// 33) for the app that is at the front right now. So the app forward
    /// first, a short wait, then the key.
    static func showAppWindows(of app: NSRunningApplication) {
        guard AXIsProcessTrusted() else { return }
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            post(125)
        }
    }

    nonisolated private static func post(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = [.maskControl, .maskSecondaryFn]
            event?.post(tap: .cghidEventTap)
        }
    }
}
