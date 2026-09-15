import Foundation

/// Liest aus `system_profiler SPBluetoothDataType -json`, ob Bluetooth an ist.
///
/// Warum dieser Umweg: IOBluetooth fragt auf aktuellen macOS-Versionen nach
/// einer Bluetooth-Freigabe (Dialog), und der alte Schluessel
/// `ControllerPowerState` in /Library/Preferences/com.apple.Bluetooth.plist
/// existiert auf macOS 26 nicht mehr (gemessen 14.09.). system_profiler
/// braucht keine Freigabe und antwortet in ~165 ms.
public enum BluetoothStatus {
    /// `true` an, `false` aus, `nil` wenn die Ausgabe nicht lesbar ist.
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
