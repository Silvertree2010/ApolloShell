import AppKit
import Carbon.HIToolbox

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
