import AppKit
import CoreGraphics

@MainActor
enum SpaceSwitcher {
    private static let left: CGKeyCode = 123
    private static let right: CGKeyCode = 124
    private static let stepDelay: TimeInterval = 0.12

    static func step(_ delta: Int) {
        guard delta != 0, AXIsProcessTrusted() else { return }
        let key = delta > 0 ? right : left
        for index in 0..<abs(delta) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * stepDelay) {
                post(key)
            }
        }
    }

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
