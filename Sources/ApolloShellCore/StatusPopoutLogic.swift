import Foundation

public enum StatusPopoutKind: String, CaseIterable, Sendable {
    case wifi
    case bluetooth
    case battery
}

public enum StatusPopoutSignal {
    public static func bars(rssi: Int?) -> Int {
        guard let rssi, rssi != 0 else { return 0 }
        switch rssi {
        case (-55)...: return 3
        case (-67)...: return 2
        case (-75)...: return 1
        default: return 0
        }
    }

    public static func quality(rssi: Int?) -> String {
        guard let rssi, rssi != 0 else { return String(localized: "No Signal") }
        switch rssi {
        case (-55)...: return String(localized: "Excellent")
        case (-67)...: return String(localized: "Good")
        case (-75)...: return String(localized: "Fair")
        default: return String(localized: "Weak")
        }
    }

    public static func signalToNoise(rssi: Int?, noise: Int?) -> Int? {
        guard let rssi, let noise, rssi != 0, noise != 0 else { return nil }
        return rssi - noise
    }

    public static func phyModeName(rawValue: Int) -> String? {
        switch rawValue {
        case 1: "802.11a"
        case 2: "802.11b"
        case 3: "802.11g"
        case 4: "Wi-Fi 4 (802.11n)"
        case 5: "Wi-Fi 5 (802.11ac)"
        case 6: "Wi-Fi 6 (802.11ax)"
        case 7: "Wi-Fi 7 (802.11be)"
        default: nil
        }
    }

    public static func bandName(rawValue: Int) -> String? {
        switch rawValue {
        case 1: "2,4 GHz"
        case 2: "5 GHz"
        case 3: "6 GHz"
        default: nil
        }
    }
}

public enum StatusPopoutDuration {
    public static func text(minutes: Int) -> String? {
        guard minutes > 0 else { return nil }
        let hours = minutes / 60, rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return String(localized: "\(rest)m")
        case (_, 0): return String(localized: "\(hours)h")
        default: return String(localized: "\(hours)h \(rest)m")
        }
    }
}

public enum StatusPopoutBatteryText {
    public static func state(_ battery: BatteryState) -> String {
        if battery.charging { return String(localized: "Charging") }
        return battery.onAC ? String(localized: "On Power") : String(localized: "Battery")
    }

    public static func time(_ battery: BatteryState, minutesToEmpty: Int, minutesToFull: Int) -> String {
        if battery.charging {
            if let text = StatusPopoutDuration.text(minutes: minutesToFull) { return String(localized: "Full in \(text)") }
            return String(localized: "Calculating charge time…")
        }
        if battery.onAC {
            return battery.level >= 100 ? String(localized: "Fully Charged") : String(localized: "Not Charging Right Now")
        }
        if let text = StatusPopoutDuration.text(minutes: minutesToEmpty) { return String(localized: "\(text) Left") }
        return String(localized: "Calculating time remaining…")
    }
}

public enum StatusPopoutBatteryHealth {
    public static func percent(rawMax: Int?, nominal: Int?, design: Int?) -> Int? {
        guard let design, design > 0, let full = [rawMax, nominal].compactMap({ $0 }).first(where: { $0 > 0 })
        else { return nil }
        return min(100, Int((Double(full) / Double(design) * 100).rounded()))
    }
}

public enum StatusPopoutPlacement {
    public static func top(anchorY: Double, height: Double, containerHeight: Double) -> Double {
        let wanted = anchorY - height / 2
        return max(0, min(wanted, containerHeight - height))
    }
}
