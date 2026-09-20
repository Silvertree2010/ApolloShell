import Foundation

/// Which detail window next to the bar is open (Caelestia:
/// modules/bar/popouts, the names "network", "bluetooth", "battery").
public enum StatusPopoutKind: String, CaseIterable, Sendable {
    case wifi
    case bluetooth
    case battery
}

/// Puts the Wi-Fi signal into words and bars.
///
/// The same thresholds as the symbol in the bar (`StatusGlyphs.wifi`), so that
/// the capsule and the detail window never claim different things.
public enum StatusPopoutSignal {
    /// Filled bars out of three. 0 means: no signal or not connected.
    public static func bars(rssi: Int?) -> Int {
        guard let rssi, rssi != 0 else { return 0 }
        // The brackets are needed: Swift reads `-55...` as a minus before `55...`.
        switch rssi {
        case (-55)...: return 3
        case (-67)...: return 2
        case (-75)...: return 1
        default: return 0
        }
    }

    /// A short verdict next to the dBm number.
    public static func quality(rssi: Int?) -> String {
        guard let rssi, rssi != 0 else { return String(localized: "No Signal") }
        switch rssi {
        case (-55)...: return String(localized: "Excellent")
        case (-67)...: return String(localized: "Good")
        case (-75)...: return String(localized: "Fair")
        default: return String(localized: "Weak")
        }
    }

    /// The distance from signal to noise in dB - it says more about the
    /// connection than the signal alone. `nil` when a value is missing.
    public static func signalToNoise(rssi: Int?, noise: Int?) -> Int? {
        guard let rssi, let noise, rssi != 0, noise != 0 else { return nil }
        return rssi - noise
    }

    /// CoreWLAN's `CWPHYMode` (the raw value) as a standard name. Raw values
    /// instead of the enumeration, so that this stays testable without CoreWLAN.
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

    /// CoreWLAN's `CWChannelBand` (the raw value) as a frequency.
    public static func bandName(rawValue: Int) -> String? {
        switch rawValue {
        case 1: "2.4 GHz"
        case 2: "5 GHz"
        case 3: "6 GHz"
        default: nil
        }
    }
}

/// The duration for the battery: "2h 15m", "45m", "1h".
public enum StatusPopoutDuration {
    /// `nil` for 0 or negative values - IOKit reports -1 while it is still
    /// working it out; then "calculating" should stand there, not "0m".
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

/// The battery state in words for the detail window.
public enum StatusPopoutBatteryText {
    /// The short form under the big percentage.
    public static func state(_ battery: BatteryState) -> String {
        if battery.charging { return String(localized: "Charging") }
        return battery.onAC ? String(localized: "On Power") : String(localized: "Battery")
    }

    /// The second line as in Caelestia: the time left on battery, the time
    /// to full while charging. Minutes as from IOKit (-1 = still working).
    public static func time(_ battery: BatteryState, minutesToEmpty: Int, minutesToFull: Int) -> String {
        if battery.charging {
            if let text = StatusPopoutDuration.text(minutes: minutesToFull) { return String(localized: "Full in \(text)") }
            return String(localized: "Calculating charge time…")
        }
        if battery.onAC {
            // On power, but not charging: full, or macOS is holding the charge
            // (optimised charging, a charge limit).
            return battery.level >= 100 ? String(localized: "Fully Charged") : String(localized: "Not Charging Right Now")
        }
        if let text = StatusPopoutDuration.text(minutes: minutesToEmpty) { return String(localized: "\(text) Left") }
        return String(localized: "Calculating time remaining…")
    }
}

/// The maximum capacity of the battery in percent of the factory capacity.
public enum StatusPopoutBatteryHealth {
    /// Out of the IORegistry (AppleSmartBattery), everything in mAh:
    /// `AppleRawMaxCapacity` first, otherwise `NominalChargeCapacity`.
    ///
    /// Capped at 100: a young battery often lies above it (measured 14.09.:
    /// 8694 of 8579 mAh = 101 %), and Apple then shows "Maximum Capacity
    /// 100 %" (system_profiler SPPowerDataType). So the two agree.
    public static func percent(rawMax: Int?, nominal: Int?, design: Int?) -> Int? {
        guard let design, design > 0, let full = [rawMax, nominal].compactMap({ $0 }).first(where: { $0 > 0 })
        else { return nil }
        return min(100, Int((Double(full) / Double(design) * 100).rounded()))
    }
}

/// Where the detail window stands vertically (Caelestia: ClipWrapper.y).
public enum StatusPopoutPlacement {
    /// The top edge in an area of the height `containerHeight` counted
    /// downwards: centred on `anchorY`, but fully inside the area. When the
    /// window is taller than the area, the top edge holds.
    public static func top(anchorY: Double, height: Double, containerHeight: Double) -> Double {
        let wanted = anchorY - height / 2
        return max(0, min(wanted, containerHeight - height))
    }
}
