import Foundation

/// Battery state as reported by IOKit (IOPSCopyPowerSourcesInfo).
public struct BatteryState: Equatable, Sendable {
    public var level: Int
    public var charging: Bool
    public var onAC: Bool

    public init(level: Int, charging: Bool, onAC: Bool) {
        self.level = level
        self.charging = charging
        self.onAC = onAC
    }
}

/// Which SF Symbol the status bar's status icons show.
///
/// As with Caelestia, they show the real state (WiFi strength, battery
/// level, charging). A placeholder battery showing "full" would be misleading.
public enum StatusGlyphs {
    /// Battery in quarter steps; the bolt while charging. `nil` means: no
    /// battery (desktop Mac), so the bar shows none.
    public static func batterySymbol(_ state: BatteryState?) -> String? {
        guard let state else { return nil }
        if state.charging { return "battery.100percent.bolt" }
        switch state.level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// WiFi symbol and fill level for SF Symbols' variableValue (0...1,
    /// three bars). Thresholds in dBm as usual: -55 and up full, -67 and up
    /// two thirds, -75 and up one third, below that nearly empty.
    public static func wifi(powerOn: Bool, rssi: Int?) -> (symbol: String, strength: Double) {
        guard powerOn else { return ("wifi.slash", 1) }
        guard let rssi, rssi != 0 else { return ("wifi", 0) }
        // Parentheses needed: Swift reads `-55...` as minus before `55...`.
        switch rssi {
        case (-55)...: return ("wifi", 1)
        case (-67)...: return ("wifi", 0.66)
        case (-75)...: return ("wifi", 0.33)
        default: return ("wifi", 0.1)
        }
    }

    // MARK: Pill labels

    // The short texts of the status pills (`BarStatusStyle.pills`). A pill
    // has room for a word, not a sentence; the full description stays in
    // the tooltip. Each says what the glyph beside it cannot: whether the
    // radio is on, how full the battery is.

    /// "Wi-Fi" while on, "Off" when switched off.
    public static func wifiPillText(powerOn: Bool) -> String {
        powerOn ? String(localized: "Wi-Fi") : String(localized: "Off")
    }

    /// "On" or "Off"; unknown (no controller answered yet) reads as on,
    /// like the glyph, which only crosses out a radio known to be off.
    public static func bluetoothPillText(on: Bool?) -> String {
        on == false ? String(localized: "Off") : String(localized: "On")
    }

    /// "76%", `nil` without a battery - then there is no pill either.
    public static func batteryPillText(_ state: BatteryState?) -> String? {
        state.map { "\(min(max($0.level, 0), 100))%" }
    }

    /// Short description for tooltip and VoiceOver.
    public static func batteryText(_ state: BatteryState?) -> String {
        guard let state else { return String(localized: "No Battery") }
        let base = String(localized: "Battery \(state.level)%")
        let suffix = state.charging ? String(localized: ", charging") : state.onAC ? String(localized: ", on power adapter") : ""
        return base + suffix
    }
}
