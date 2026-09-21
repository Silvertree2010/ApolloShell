import AppKit
import Carbon.HIToolbox

/// Apple's "Switch to Desktop N" keyboard shortcuts, the only way to switch
/// desktops without turning System Integrity Protection off.
///
/// They are set to Super + N, so macOS itself switches when Super + N is
/// pressed: no key press is faked. (Faking control + N while Super was still
/// held switched only sometimes, because the held modifiers mixed into the
/// fake press.) They are off by default; `ensure(modifiers:)` turns them on
/// with those keys and tells the system to reload its shortcuts. Stored in
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
    /// Makes desktops 1-9 switch on `modifiers` + digit. Stored modifier bits
    /// are the same as CGEventFlags' (control 1<<18 ... command 1<<20).
    /// `changed` is true when something had to be rewritten.
    @discardableResult
    public static func ensure(modifiers: CGEventFlags) -> (shortcuts: [Int: Shortcut], changed: Bool) {
        let mask = Int(modifiers.rawValue & 0x1F_0000)
        var hotkeys = CFPreferencesCopyAppValue(key, domain) as? [String: Any] ?? [:]
        var shortcuts: [Int: Shortcut] = [:]
        var changed = false
        for number in 1...9 {
            let id = String(firstID + number - 1)
            let entry = hotkeys[id] as? [String: Any]
            let enabled = (entry?["enabled"] as? NSNumber)?.boolValue ?? false
            let parameters = ((entry?["value"] as? [String: Any])?["parameters"] as? [NSNumber])?.map(\.intValue)
            let keyCode = digitKeys[number - 1]
            shortcuts[number] = Shortcut(keyCode: CGKeyCode(keyCode), flags: CGEventFlags(rawValue: UInt64(mask)))
            if enabled, parameters == [65535, keyCode, mask] { continue }
            hotkeys[id] = [
                "enabled": true,
                "value": ["parameters": [65535, keyCode, mask], "type": "standard"],
            ] as [String: Any]
            changed = true
        }
        if changed {
            CFPreferencesSetAppValue(key, hotkeys as CFDictionary, domain)
            CFPreferencesAppSynchronize(domain)
            reloadSystemShortcuts()
        }
        return (shortcuts, changed)
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
