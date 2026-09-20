import Foundation

/// Eine Akku-Warnstufe (Caelestia: general.battery.warnLevels).
public struct BatteryWarningLevel: Equatable, Sendable {
    public let level: Int
    public let title: String
    public let message: String
    public let symbol: String
    /// Kritisch = Fehler-Farbe statt Warnung.
    public let critical: Bool

    public init(level: Int, title: String, message: String, symbol: String, critical: Bool = false) {
        self.level = level
        self.title = title
        self.message = message
        self.symbol = symbol
        self.critical = critical
    }

    public var kind: ToastKind { critical ? .error : .warning }

    /// Caelestias Vorgaben: 20, 10, 5 (kritisch), samt dem Ton der Texte.
    /// Die "criticalLevel" 3 mit Ruhezustand nach 5 s gibt es hier bewusst
    /// nicht: macOS schlaeft bei leerem Akku selbst, der Launcher loest nie
    /// eine Sitzungsaktion aus.
    public static let caelestiaDefaults: [BatteryWarningLevel] = [
        BatteryWarningLevel(level: 20, title: String(localized: "Low Battery"),
                            message: String(localized: "You should plug in a charger soon"),
                            symbol: "battery.25percent"),
        BatteryWarningLevel(level: 10, title: String(localized: "Did you see the last alert?"),
                            message: String(localized: "You'd better plug in a charger now"),
                            symbol: "battery.0percent"),
        BatteryWarningLevel(level: 5, title: String(localized: "Battery Almost Empty"),
                            message: String(localized: "PLUG IN THE CHARGER NOW!!"),
                            // Caelestia: battery_android_alert (Akku mit "!").
                            symbol: "minus.plus.batteryblock.exclamationmark.fill", critical: true),
    ]
}

/// Was der Akku an Kurzmeldungen ausloest.
public enum BatteryToastEvent: Equatable, Sendable {
    case chargerConnected
    case chargerDisconnected
    case warning(BatteryWarningLevel)
}

extension ToastText {
    public static func battery(_ event: BatteryToastEvent) -> Content {
        switch event {
        case .chargerConnected: chargerConnected
        case .chargerDisconnected: chargerDisconnected
        case .warning(let level):
            Content(title: level.title, message: level.message, symbol: level.symbol, kind: level.kind)
        }
    }
}

/// Caelestias BatteryMonitor als reine Logik.
///
/// - Warnung, wenn der Stand im Akkubetrieb eine Stufe nach unten kreuzt
///   (`neu <= Stufe < alt`). Kreuzt ein Sprung mehrere, gewinnt die
///   niedrigste (Stufen aufsteigend, erster Treffer).
/// - Am Netzteil keine Warnungen; der Stand wird nur mitgefuehrt.
/// - Einstecken setzt den Vergleichswert auf 100: zieht man gleich wieder
///   ab, kommt die Warnung fuer den aktuellen Stand noch einmal.
/// - Anders als Caelestia beim Start keine Meldung: der Anfangszustand ist
///   Ausgangspunkt, nicht Ereignis (Caelestia vergleicht beim Start mit 100
///   und warnt sofort).
public struct BatteryToastTracker: Sendable {
    /// Aufsteigend sortiert.
    public let levels: [BatteryWarningLevel]
    /// Caelestia: lastPercentage - der Vergleichswert fuer Stufen.
    public private(set) var reference: Int
    /// Zuletzt gesehener Stand. IOKit meldet viel oefter als nur bei neuem
    /// Prozentwert; Caelestia reagiert nur auf `percentageChanged`.
    public private(set) var percent: Int
    public private(set) var onBattery: Bool

    public init(levels: [BatteryWarningLevel] = BatteryWarningLevel.caelestiaDefaults, percent: Int, onBattery: Bool) {
        self.levels = levels.sorted { $0.level < $1.level }
        self.reference = percent
        self.percent = percent
        self.onBattery = onBattery
    }

    public mutating func update(percent newPercent: Int, onBattery nowOnBattery: Bool) -> [BatteryToastEvent] {
        if nowOnBattery != onBattery {
            onBattery = nowOnBattery
            percent = newPercent
            guard nowOnBattery else {
                reference = 100
                return [.chargerConnected]
            }
            var events: [BatteryToastEvent] = [.chargerDisconnected]
            if let level = checkLevels(newPercent) { events.append(.warning(level)) }
            return events
        }
        guard newPercent != percent else { return [] }
        percent = newPercent
        guard let level = checkLevels(newPercent) else { return [] }
        return [.warning(level)]
    }

    /// Caelestia: handleBatteryWarnings.
    private mutating func checkLevels(_ p: Int) -> BatteryWarningLevel? {
        defer { reference = p }
        guard onBattery else { return nil }
        return levels.first { p <= $0.level && reference > $0.level }
    }
}
