import Foundation

// MARK: - Netzwerk

/// Summierte Byte-Zaehler der gezaehlten Netzwerk-Schnittstellen seit dem
/// Systemstart. 64 Bit aus if_data64 (sysctl NET_RT_IFLIST2): die Zaehler
/// von getifaddrs sind nur 32 Bit und fangen nach 4 GB wieder bei null an.
public struct NetCounters: Equatable, Sendable {
    public var received: UInt64
    public var sent: UInt64

    public init(received: UInt64, sent: UInt64) {
        self.received = received
        self.sent = sent
    }

    public static let zero = NetCounters(received: 0, sent: 0)
}

/// Datenrate in Byte pro Sekunde.
public struct NetRate: Equatable, Sendable {
    public var download: Double
    public var upload: Double

    public init(download: Double, upload: Double) {
        self.download = download
        self.upload = upload
    }
}

public enum NetworkMath {
    /// Welche Schnittstellen in die Summe gehen. Nicht dabei: Loopback (lo0,
    /// der Verkehr verlaesst den Mac nie), Punkt-zu-Punkt-Tunnel (utun: VPNs
    /// wie Tailscale oder Mullvad - ihr Verkehr laeuft verschluesselt ein
    /// zweites Mal ueber en0; gemessen 14.09.: utun6 1,0 GB rein, en0 3,8 GB,
    /// die Summe haette ein Viertel zu viel gezeigt) und Bruecken (bridge0
    /// zaehlt die Pakete seiner Mitglieder en1/en2 nochmals).
    public static func counts(flags: Int32, type: UInt8) -> Bool {
        if flags & IFF_LOOPBACK != 0 { return false }
        if flags & IFF_POINTOPOINT != 0 { return false }
        return Int32(type) != IFT_BRIDGE
    }

    /// Unterschied zwischen zwei Messungen. `nil`, wenn ein Zaehler kleiner
    /// wurde: dann ist eine Schnittstelle weggefallen (VPN aus, Adapter
    /// ab) - die Differenz waere Unsinn, bei UInt64 sogar ein Ueberlauf.
    public static func delta(from old: NetCounters, to new: NetCounters) -> NetCounters? {
        guard new.received >= old.received, new.sent >= old.sent else { return nil }
        return NetCounters(received: new.received - old.received, sent: new.sent - old.sent)
    }

    /// Rate zwischen zwei Messungen; `nil` bei zurueckgesetztem Zaehler oder
    /// wenn keine Zeit dazwischen liegt.
    public static func rate(from old: NetCounters, to new: NetCounters, seconds: TimeInterval) -> NetRate? {
        guard seconds > 0, let delta = delta(from: old, to: new) else { return nil }
        return NetRate(download: Double(delta.received) / seconds, upload: Double(delta.sent) / seconds)
    }
}

/// Rate und Gesamtsumme aus fortlaufenden Zaehlerstaenden.
///
/// Die Summe zaehlt ab der ersten Messung und auch ueber Pausen hinweg (die
/// Zaehler des Systems laufen weiter). Die Rate nicht: ueber eine Pause
/// gemittelt waere sie falsch, deshalb gibt die erste Messung danach keine.
public struct NetworkMeter: Sendable {
    public private(set) var rate: NetRate?
    public private(set) var total = NetCounters.zero
    private var last: NetCounters?
    private var lastTime: TimeInterval = 0
    private var paused = true

    public init() {}

    public mutating func pause() {
        paused = true
        rate = nil
    }

    public mutating func add(_ counters: NetCounters, at time: TimeInterval) {
        defer {
            self.last = counters
            self.lastTime = time
            self.paused = false
        }
        guard let last, let delta = NetworkMath.delta(from: last, to: counters) else {
            rate = nil
            return
        }
        total.received += delta.received
        total.sent += delta.sent
        rate = paused ? nil : NetworkMath.rate(from: last, to: counters, seconds: time - lastTime)
    }
}

// MARK: - Verlauf

/// Die letzten `capacity` Messwerte, aeltester zuerst - fuer die Verlaufslinien.
public struct SampleHistory: Equatable, Sendable {
    public let capacity: Int
    public private(set) var values: [Double] = []

    public init(capacity: Int) {
        precondition(capacity > 0, "Verlauf braucht Platz fuer mindestens einen Wert")
        self.capacity = capacity
    }

    public mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }

    public mutating func removeAll() {
        values.removeAll(keepingCapacity: true)
    }

    public var peak: Double { values.max() ?? 0 }
}

/// Punkte der Verlaufslinie im Einheitsquadrat (x von links, y von unten).
public enum Sparkline {
    /// Obergrenze der y-Achse: das Maximum im Verlauf, aber nie unter `floor`.
    /// Ohne Boden fuellte ein Leerlauf-Rinnsal von 200 B/s die ganze Hoehe und
    /// saehe aus wie Volllast.
    public static func scale(peak: Double, floor: Double) -> Double {
        max(peak, floor)
    }

    /// Rechtsbuendig: der neueste Wert steht immer am rechten Rand; solange
    /// der Puffer nicht voll ist, waechst die Linie von rechts herein - so
    /// wandert jeder Punkt pro Messung um genau einen Schritt.
    public static func points(_ values: [Double], capacity: Int, scale: Double) -> [CGPoint] {
        guard capacity > 0, !values.isEmpty else { return [] }
        let shown = values.suffix(capacity)
        let step = capacity > 1 ? 1 / Double(capacity - 1) : 0
        let offset = capacity - shown.count
        return shown.enumerated().map { index, value in
            CGPoint(
                x: capacity > 1 ? Double(offset + index) * step : 1,
                y: scale > 0 ? min(max(value / scale, 0), 1) : 0
            )
        }
    }
}

// MARK: - Texte

/// Byte-Angaben mit dem Dezimaltrennzeichen der Sprache ("1,2 MB" auf
/// Deutsch, "1.2 MB" auf Englisch), Leerzeichen vor der Einheit.
public enum ByteFormat {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    /// Dezimal (1 KB = 1000 B) wie Finder und Aktivitaetsanzeige beim
    /// Netzwerk; `binary` (1024) fuer Arbeitsspeicher - sonst stuenden
    /// 24 GB RAM als "26 GB" da. Unter 10 eine Nachkommastelle ("1,2 MB"),
    /// darueber ganze Zahlen ("340 KB"): die Breite bleibt ruhig.
    public static func bytes(_ value: Double, binary: Bool = false, locale: Locale = .current) -> String {
        let base: Double = binary ? 1024 : 1000
        var amount = value.isFinite ? max(value, 0) : 0
        var unit = 0
        // Erst runden, dann Einheit waehlen: sonst hiesse 999,7 KB "1000 KB".
        while unit < units.count - 1, shown(amount, unit: unit) >= 1000 {
            amount /= base
            unit += 1
        }
        if unit == 0 { return "\(Int(amount.rounded())) B" }
        let tenths = Int((amount * 10).rounded())
        if tenths < 100 {
            return "\(tenths / 10)\(locale.decimalSeparator ?? ".")\(tenths % 10) \(units[unit])"
        }
        return "\(Int(amount.rounded())) \(units[unit])"
    }

    /// Datenrate, z. B. "1,2 MB/s".
    public static func rate(_ bytesPerSecond: Double, locale: Locale = .current) -> String {
        bytes(bytesPerSecond, locale: locale) + "/s"
    }

    /// "412 GB von 994 GB".
    public static func usage(used: UInt64, total: UInt64, binary: Bool = false, locale: Locale = .current) -> String {
        let used = bytes(Double(used), binary: binary, locale: locale)
        let total = bytes(Double(total), binary: binary, locale: locale)
        return String(localized: "\(used) von \(total)")
    }

    /// Der Wert, wie er nach dem Runden angezeigt wuerde.
    private static func shown(_ amount: Double, unit: Int) -> Double {
        unit == 0 || amount >= 9.95 ? amount.rounded() : (amount * 10).rounded() / 10
    }
}

public enum PerformanceText {
    /// Anteil als "37 %"; ohne Messwert ein Strich statt einer falschen Null.
    public static func percent(_ fraction: Double?) -> String {
        guard let fraction, fraction.isFinite else { return "–" }
        return "\(Int((min(max(fraction, 0), 1) * 100).rounded())) %"
    }
}

/// Texte und Fuellstand fuer den Akku-Tank.
public enum BatteryTankText {
    /// Fuellhoehe 0...1.
    public static func fill(_ state: BatteryState) -> Double {
        min(max(Double(state.level) / 100, 0), 1)
    }

    public static func percent(_ state: BatteryState) -> String {
        "\(min(max(state.level, 0), 100)) %"
    }

    /// `minutes`: bis voll (beim Laden) bzw. bis leer (am Akku), wie IOKit
    /// sie meldet. Null oder negativ heisst "wird noch berechnet".
    public static func status(_ state: BatteryState, minutes: Int?) -> String {
        let time = minutes.flatMap { $0 > 0 ? UptimeText.format(seconds: TimeInterval($0) * 60) : nil }
        if state.charging { return time.map { String(localized: "Voll in \($0)") } ?? String(localized: "Lädt") }
        if state.onAC { return state.level >= 100 ? String(localized: "Geladen") : String(localized: "Am Netzteil") }
        return time.map { String(localized: "Noch \($0)") } ?? String(localized: "Berechne …")
    }
}
