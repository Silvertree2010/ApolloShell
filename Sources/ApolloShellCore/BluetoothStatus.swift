import Foundation

public enum BluetoothStatus {
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
