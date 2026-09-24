import Foundation

public struct StatusPopoutBluetoothBattery: Equatable, Sendable {
    public enum Part: String, Sendable {
        case main, left, right, `case`
    }

    public var part: Part
    public var percent: Int

    public init(part: Part, percent: Int) {
        self.part = part
        self.percent = percent
    }

    public var label: String? {
        switch part {
        case .main: nil
        case .left: "L"
        case .right: "R"
        case .case: "Case"
        }
    }
}

public struct StatusPopoutBluetoothDevice: Equatable, Sendable, Identifiable {
    public var name: String
    public var minorType: String?
    public var connected: Bool
    public var batteries: [StatusPopoutBluetoothBattery]

    public init(name: String, minorType: String?, connected: Bool, batteries: [StatusPopoutBluetoothBattery]) {
        self.name = name
        self.minorType = minorType
        self.connected = connected
        self.batteries = batteries
    }

    public var id: String { "\(connected ? 1 : 0)-\(name)" }

    public var symbol: String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("iphone") { return "iphone" }
        if lower.contains("ipad") { return "ipad" }
        switch minorType?.lowercased() {
        case "headphones"?, "headset"?: return "headphones"
        case "keyboard"?: return "keyboard"
        case "mouse"?: return "computermouse"
        case "trackpad"?: return "rectangle.and.hand.point.up.left"
        case "speaker"?, "loudspeaker"?: return "hifispeaker"
        case "gamepad"?, "joystick"?: return "gamecontroller"
        default: return "dot.radiowaves.left.and.right"
        }
    }
}

public struct StatusPopoutBluetoothSnapshot: Equatable, Sendable {
    public var powerOn: Bool?
    public var devices: [StatusPopoutBluetoothDevice]

    public init(powerOn: Bool?, devices: [StatusPopoutBluetoothDevice]) {
        self.powerOn = powerOn
        self.devices = devices
    }

    public var connected: [StatusPopoutBluetoothDevice] { devices.filter(\.connected) }
    public var pairedCount: Int { devices.count }
}

public enum StatusPopoutBluetoothParser {
    public static func snapshot(fromSystemProfilerJSON data: Data) -> StatusPopoutBluetoothSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = (root["SPBluetoothDataType"] as? [[String: Any]])?.first
        else { return nil }
        let devices = parse(entry["device_connected"], connected: true)
            + parse(entry["device_not_connected"], connected: false)
        return StatusPopoutBluetoothSnapshot(
            powerOn: BluetoothStatus.powerOn(fromSystemProfilerJSON: data),
            devices: devices
        )
    }

    private static let batteryKeys: [(String, StatusPopoutBluetoothBattery.Part)] = [
        ("device_batteryLevelMain", .main),
        ("device_batteryLevelLeft", .left),
        ("device_batteryLevelRight", .right),
        ("device_batteryLevelCase", .case),
    ]

    private static func parse(_ value: Any?, connected: Bool) -> [StatusPopoutBluetoothDevice] {
        guard let list = value as? [[String: Any]] else { return [] }
        return list.flatMap { item in
            item.compactMap { name, props -> StatusPopoutBluetoothDevice? in
                guard let props = props as? [String: Any] else { return nil }
                let batteries = connected ? batteryKeys.compactMap { key, part in
                    percent(props[key]).map { StatusPopoutBluetoothBattery(part: part, percent: $0) }
                } : []
                return StatusPopoutBluetoothDevice(
                    name: name,
                    minorType: props["device_minorType"] as? String,
                    connected: connected,
                    batteries: batteries
                )
            }
        }
    }

    static func percent(_ value: Any?) -> Int? {
        let number: Int?
        switch value {
        case let int as Int: number = int
        case let text as String:
            number = Int(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
        default: number = nil
        }
        guard let number, (0...100).contains(number) else { return nil }
        return number
    }
}
