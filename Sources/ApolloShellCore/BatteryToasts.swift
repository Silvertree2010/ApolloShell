import Foundation

/// One battery warning level (Caelestia: general.battery.warnLevels).
public struct BatteryWarningLevel: Equatable, Sendable {
    public let level: Int
    public let title: String
    public let message: String
    public let symbol: String
    /// Critical = the error color instead of a warning.
    public let critical: Bool

    public init(level: Int, title: String, message: String, symbol: String, critical: Bool = false) {
        self.level = level
        self.title = title
        self.message = message
        self.symbol = symbol
        self.critical = critical
    }

    public var kind: ToastKind { critical ? .error : .warning }

    /// Caelestia's defaults: 20, 10, 5 (critical), together with the tone of
    /// the texts. The "criticalLevel" 3 with sleep after 5 s is deliberately
    /// not here: macOS sleeps by itself with an empty battery, and the launcher
    /// never sets off a session action.
    public static let caelestiaDefaults: [BatteryWarningLevel] = [
        BatteryWarningLevel(level: 20, title: String(localized: "Low Battery"),
                            message: String(localized: "You should plug in a charger soon"),
                            symbol: "battery.25percent"),
        BatteryWarningLevel(level: 10, title: String(localized: "Did you see the last alert?"),
                            message: String(localized: "You'd better plug in a charger now"),
                            symbol: "battery.0percent"),
        BatteryWarningLevel(level: 5, title: String(localized: "Battery Almost Empty"),
                            message: String(localized: "PLUG IN THE CHARGER NOW!!"),
                            // Caelestia: battery_android_alert (a battery with "!").
                            symbol: "minus.plus.batteryblock.exclamationmark.fill", critical: true),
    ]
}

/// What the battery sets off in toasts.
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

/// Caelestia's BatteryMonitor as plain logic.
///
/// - A warning when the level crosses a step downwards on battery
///   (`new <= step < old`). When one jump crosses several, the lowest wins
///   (the steps sorted upwards, the first hit).
/// - On the power adapter no warnings; the level is only kept up.
/// - Plugging in sets the comparison value to 100: unplugging right away
///   brings the warning for the current level once more.
/// - Unlike Caelestia, no toast on the start: the starting state is the
///   starting point, not an event (Caelestia compares with 100 on the start
///   and warns right away).
public struct BatteryToastTracker: Sendable {
    /// Sorted upwards.
    public let levels: [BatteryWarningLevel]
    /// Caelestia: lastPercentage - the comparison value for the steps.
    public private(set) var reference: Int
    /// The level that was seen last. IOKit reports far more often than only on
    /// a new percentage; Caelestia reacts only to `percentageChanged`.
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
