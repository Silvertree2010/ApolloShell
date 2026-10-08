import Foundation

/// Welches Detailfenster neben der Leiste offen ist (Caelestia:
/// modules/bar/popouts, Namen "network", "bluetooth", "battery").
public enum StatusPopoutKind: String, CaseIterable, Sendable {
    case wifi
    case bluetooth
    case battery
    case stack
    case sound
}

/// WLAN-Signal in Worte und Balken fassen.
///
/// Dieselben Schwellen wie das Symbol in der Leiste (`StatusGlyphs.wifi`),
/// damit Kapsel und Detailfenster nie Verschiedenes behaupten.
public enum StatusPopoutSignal {
    /// Gefuellte Balken von drei. 0 heisst: kein Signal bzw. nicht verbunden.
    public static func bars(rssi: Int?) -> Int {
        guard let rssi, rssi != 0 else { return 0 }
        // Klammern noetig: `-55...` liest Swift als Minus vor `55...`.
        switch rssi {
        case (-55)...: return 3
        case (-67)...: return 2
        case (-75)...: return 1
        default: return 0
        }
    }

    /// Kurzurteil neben der dBm-Zahl.
    public static func quality(rssi: Int?) -> String {
        guard let rssi, rssi != 0 else { return String(localized: "No Signal") }
        switch rssi {
        case (-55)...: return String(localized: "Excellent")
        case (-67)...: return String(localized: "Good")
        case (-75)...: return String(localized: "Fair")
        default: return String(localized: "Weak")
        }
    }

    /// Abstand Signal zu Rauschen in dB - sagt mehr ueber die Verbindung als
    /// das Signal allein. `nil`, wenn einer der Werte fehlt (0 = unbekannt).
    public static func signalToNoise(rssi: Int?, noise: Int?) -> Int? {
        guard let rssi, let noise, rssi != 0, noise != 0 else { return nil }
        return rssi - noise
    }

    /// CoreWLANs `CWPHYMode` (Rohwert) als Standardname. Rohwerte statt der
    /// Aufzaehlung, damit das hier ohne CoreWLAN testbar bleibt.
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

    /// CoreWLANs `CWChannelBand` (Rohwert) als Frequenz.
    public static func bandName(rawValue: Int) -> String? {
        switch rawValue {
        case 1: "2,4 GHz"
        case 2: "5 GHz"
        case 3: "6 GHz"
        default: nil
        }
    }
}

/// Dauer fuer den Akku: "2 Std 15 Min", "45 Min", "1 Std".
public enum StatusPopoutDuration {
    /// `nil` fuer 0 oder negative Werte - IOKit meldet -1, solange es noch
    /// rechnet; dann soll "wird berechnet" stehen, nicht "0 Min".
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

/// Akkuzustand in Worten fuer das Detailfenster.
public enum StatusPopoutBatteryText {
    /// Kurzform unter der grossen Prozentzahl.
    public static func state(_ battery: BatteryState) -> String {
        if battery.charging { return String(localized: "Charging") }
        return battery.onAC ? String(localized: "On Power") : String(localized: "Battery")
    }

    /// Zweite Zeile wie bei Caelestia: Restlaufzeit auf Akku, Zeit bis voll
    /// beim Laden. Minuten wie von IOKit (-1 = rechnet noch, 0 = keine).
    public static func time(_ battery: BatteryState, minutesToEmpty: Int, minutesToFull: Int) -> String {
        if battery.charging {
            if let text = StatusPopoutDuration.text(minutes: minutesToFull) { return String(localized: "Full in \(text)") }
            return String(localized: "Calculating charge time…")
        }
        if battery.onAC {
            // Am Netz, aber nicht am Laden: voll, oder macOS haelt die
            // Ladung an (optimiertes Laden, Ladegrenze).
            return battery.level >= 100 ? String(localized: "Fully Charged") : String(localized: "Not Charging Right Now")
        }
        if let text = StatusPopoutDuration.text(minutes: minutesToEmpty) { return String(localized: "\(text) Left") }
        return String(localized: "Calculating time remaining…")
    }
}

/// Maximale Kapazitaet des Akkus in Prozent der Werkskapazitaet.
public enum StatusPopoutBatteryHealth {
    /// Aus der IORegistry (AppleSmartBattery), alles in mAh:
    /// `AppleRawMaxCapacity` zuerst, sonst `NominalChargeCapacity`.
    ///
    /// Gedeckelt bei 100: ein junger Akku liegt oft darueber (gemessen 14.09.:
    /// 8694 von 8579 mAh = 101 %), und Apple zeigt dann "Maximale Kapazitaet
    /// 100 %" (system_profiler SPPowerDataType). So stimmen beide ueberein.
    public static func percent(rawMax: Int?, nominal: Int?, design: Int?) -> Int? {
        guard let design, design > 0, let full = [rawMax, nominal].compactMap({ $0 }).first(where: { $0 > 0 })
        else { return nil }
        return min(100, Int((Double(full) / Double(design) * 100).rounded()))
    }
}

/// Wo das Detailfenster senkrecht steht (Caelestia: ClipWrapper.y).
public enum StatusPopoutPlacement {
    /// Oberkante in einem nach unten zaehlenden Bereich der Hoehe
    /// `containerHeight`: mittig auf `anchorY`, aber ganz im Bereich.
    /// Ist das Fenster hoeher als der Bereich, gilt die Oberkante.
    public static func top(anchorY: Double, height: Double, containerHeight: Double) -> Double {
        let wanted = anchorY - height / 2
        return max(0, min(wanted, containerHeight - height))
    }
}

public enum StatusPopoutJoin {
    public static func radii(top: Double, bottom: Double, minY: Double, maxY: Double,
                             width: Double, join: Double) -> (top: Double, bottom: Double) {
        let cap = max(0, min(join, width))
        return (min(cap, max(0, top - minY)), min(cap, max(0, maxY - bottom)))
    }
}

public struct SpeedResult: Equatable, Sendable {
    public var down: Double
    public var up: Double
    public var rpm: Double?
    public var rtt: Double?

    public static func parse(_ data: Data) -> SpeedResult? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = (o["dl_throughput"] as? NSNumber)?.doubleValue,
              let u = (o["ul_throughput"] as? NSNumber)?.doubleValue else { return nil }
        return SpeedResult(down: d, up: u, rpm: (o["responsiveness"] as? NSNumber)?.doubleValue,
                           rtt: (o["base_rtt"] as? NSNumber)?.doubleValue)
    }

    public init(down: Double, up: Double, rpm: Double? = nil, rtt: Double? = nil) {
        self.down = down
        self.up = up
        self.rpm = rpm
        self.rtt = rtt
    }

    public static func live(_ line: String) -> SpeedResult? {
        let n = line.replacingOccurrences(of: "\u{1B}[2K", with: "")
        guard let d = num(n, after: "Downlink: "), let u = num(n, after: "Uplink: ") else { return nil }
        let rpm = num(n, after: "Mbps, ")
        return SpeedResult(down: d * 1_000_000, up: u * 1_000_000, rpm: (rpm ?? 0) > 0 ? rpm : nil)
    }

    public static func summary(_ text: String, last: SpeedResult?) -> SpeedResult? {
        let d = num(text, after: "Downlink capacity: ").map { $0 * 1_000_000 } ?? last?.down
        let u = num(text, after: "Uplink capacity: ").map { $0 * 1_000_000 } ?? last?.up
        guard let d, let u else { return nil }
        var rpm = last?.rpm
        if let r = text.range(of: "Responsiveness:"), let bar = text[r.upperBound...].range(of: "| ") {
            rpm = num(String(text[bar.upperBound...]), after: "") ?? rpm
        }
        return SpeedResult(down: d, up: u, rpm: rpm, rtt: nil)
    }

    static func num(_ s: String, after key: String) -> Double? {
        guard let r = key.isEmpty ? s.startIndex..<s.startIndex : s.range(of: key) else { return nil }
        let tail = s[r.upperBound...].prefix { $0.isNumber || $0 == "." }
        return Double(tail)
    }

    public static func mbit(_ bps: Double) -> String {
        let m = bps / 1_000_000
        return m >= 100 ? "\(Int(m.rounded())) Mbit/s" : String(format: "%.1f Mbit/s", m)
    }

    public var responsiveness: String? {
        guard let rpm else { return nil }
        let q = rpm >= 800 ? String(localized: "High") : rpm >= 300 ? String(localized: "Medium") : String(localized: "Low")
        return "\(q) · \(Int(rpm.rounded())) RPM"
    }
}
