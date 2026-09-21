import AppKit
import Carbon.HIToolbox

/// Apple's "Switch to Desktop N" keyboard shortcuts, the only way to switch
/// desktops without turning System Integrity Protection off: the engine
/// presses them.
///
/// They are off by default. `ensure()` turns missing or disabled ones on with
/// Apple's default (control + N) and keeps any the user set up differently,
/// then tells the system to reload its shortcuts. Stored in
/// com.apple.symbolichotkeys, ids 118-126 for desktops 1-9.
public enum DesktopShortcuts {
    public struct Shortcut: Sendable, Equatable {
        public let keyCode: CGKeyCode
        public let flags: CGEventFlags
    }

    private static var domain: CFString { "com.apple.symbolichotkeys" as CFString }
    private static var key: CFString { "AppleSymbolicHotKeys" as CFString }
    private static let firstID = 118
    private static let digitKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                    kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
    /// The shortcut modifier mask as stored (NSEvent modifier bits).
    private static let control = 262_144

    /// Makes sure desktops 1-9 have working shortcuts and returns them.
    /// `changed` is true when something had to be turned on.
    @discardableResult
    public static func ensure() -> (shortcuts: [Int: Shortcut], changed: Bool) {
        var hotkeys = CFPreferencesCopyAppValue(key, domain) as? [String: Any] ?? [:]
        var shortcuts: [Int: Shortcut] = [:]
        var changed = false
        for number in 1...9 {
            let id = String(firstID + number - 1)
            let entry = hotkeys[id] as? [String: Any]
            let enabled = (entry?["enabled"] as? NSNumber)?.boolValue ?? false
            let parameters = ((entry?["value"] as? [String: Any])?["parameters"] as? [NSNumber])?.map(\.intValue)
            if enabled, let parameters, parameters.count == 3 {
                shortcuts[number] = Shortcut(keyCode: CGKeyCode(parameters[1]),
                                             flags: CGEventFlags(rawValue: UInt64(parameters[2])))
                continue
            }
            let keyCode = digitKeys[number - 1]
            hotkeys[id] = [
                "enabled": true,
                "value": ["parameters": [65535, keyCode, control], "type": "standard"],
            ] as [String: Any]
            shortcuts[number] = Shortcut(keyCode: CGKeyCode(keyCode), flags: .maskControl)
            changed = true
        }
        if changed {
            CFPreferencesSetAppValue(key, hotkeys as CFDictionary, domain)
            CFPreferencesAppSynchronize(domain)
            reloadSystemShortcuts()
        }
        return (shortcuts, changed)
    }

    /// Presses the shortcut for desktop `number`.
    public static func press(_ shortcut: Shortcut) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: down)
            // Exactly the shortcut's modifiers; keys still held (Super) must not leak in.
            event?.flags = shortcut.flags
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Makes the running system pick up changed shortcuts without a logout.
    private static func reloadSystemShortcuts() {
        let tool = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
        guard FileManager.default.isExecutableFile(atPath: tool) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["-u"]
        try? process.run()
        process.waitUntilExit()
    }
}
