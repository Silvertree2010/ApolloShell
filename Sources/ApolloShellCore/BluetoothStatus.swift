import Foundation

/// Reads whether Bluetooth is on from `system_profiler SPBluetoothDataType -json`.
///
/// Why this detour: on current macOS versions, IOBluetooth asks for a
/// Bluetooth permission (dialog), and the old key `ControllerPowerState`
/// in /Library/Preferences/com.apple.Bluetooth.plist no longer exists on
/// macOS 26 (measured 14.09.). system_profiler needs no permission and
/// answers in ~165 ms.
public enum BluetoothStatus {
    /// `true` for on, `false` for off, `nil` if the output isn't readable.
    public static func powerOn(fromSystemProfilerJSON data: Data) -> Bool? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["SPBluetoothDataType"] as? [[String: Any]],
              let controller = entries.first?["controller_properties"] as? [String: Any],
              let state = controller["controller_state"] as? String
        else { return nil }
        switch state {
        case "attrib_on": return true
        case "attrib_off": return false
        default: return nil
        }
    }
}
