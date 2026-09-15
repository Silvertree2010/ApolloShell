import Foundation

/// Akkuzustand, wie ihn IOKit (IOPSCopyPowerSourcesInfo) liefert.
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

/// Welches SF Symbol die Statussymbole der Leiste zeigen.
///
/// Wie bei Caelestia zeigen sie den echten Zustand (WLAN-Staerke, Akkustand,
/// Laden). Ein Platzhalter-Akku, der "voll" zeigt, waere irrefuehrend.
public enum StatusGlyphs {
    /// Akku in Viertelschritten; beim Laden der Blitz. `nil` heisst: kein
    /// Akku (Desktop-Mac), dann zeigt die Leiste keinen.
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

    /// WLAN-Symbol und Fuellstand fuer SF Symbols' variableValue (0...1,
    /// drei Balken). Schwellen in dBm wie ueblich: ab -55 voll, ab -67 zwei
    /// Drittel, ab -75 ein Drittel, darunter fast leer.
    public static func wifi(powerOn: Bool, rssi: Int?) -> (symbol: String, strength: Double) {
        guard powerOn else { return ("wifi.slash", 1) }
        guard let rssi, rssi != 0 else { return ("wifi", 0) }
        // Klammern noetig: `-55...` liest Swift als Minus vor `55...`.
        switch rssi {
        case (-55)...: return ("wifi", 1)
        case (-67)...: return ("wifi", 0.66)
        case (-75)...: return ("wifi", 0.33)
        default: return ("wifi", 0.1)
        }
    }

    /// Kurzbeschreibung fuer Tooltip und VoiceOver.
    public static func batteryText(_ state: BatteryState?) -> String {
        guard let state else { return String(localized: "Kein Akku") }
        let base = String(localized: "Akku \(state.level) %")
        let suffix = state.charging ? String(localized: ", lädt") : state.onAC ? String(localized: ", am Netzteil") : ""
        return base + suffix
    }
}
