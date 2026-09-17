import Foundation

/// Art einer Kurzmeldung (Caelestia: Toast.Type). Bestimmt Farbe und das
/// Symbol, falls der Aufrufer keins mitgibt.
public enum ToastKind: Sendable, Equatable {
    case info, success, warning, error

    /// Kennung fuer den Symbol-Austausch im Theme (`icons/<kennung>.png`).
    public var iconID: String {
        switch self {
        case .info: "toast-info"
        case .success: "toast-success"
        case .warning: "toast-warning"
        case .error: "toast-error"
        }
    }

    /// Caelestia: info, check_circle_unread, warning, error.
    public var defaultSymbol: String {
        switch self {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "exclamationmark.circle.fill"
        }
    }
}

/// Eine Kurzmeldung in der Warteschlange.
public struct ToastEntry: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let message: String
    public let symbol: String
    public let kind: ToastKind
    /// Ab hier schliesst sie sich selbst.
    public let deadline: Date
    /// War schon einmal wegen Ueberzahl ausgeblendet. Rueckt sie spaeter
    /// nach, blendet sie wie bei Caelestia nur ein (0.7 -> 1) statt aus dem
    /// Nichts aufzugehen - daran haengt der Uebergang der Oberflaeche.
    public internal(set) var hasBeenHidden: Bool

    public init(id: Int, title: String, message: String, symbol: String, kind: ToastKind,
                deadline: Date, hasBeenHidden: Bool = false) {
        self.id = id
        self.title = title
        self.message = message
        self.symbol = symbol
        self.kind = kind
        self.deadline = deadline
        self.hasBeenHidden = hasBeenHidden
    }
}

/// Warteschlange der Kurzmeldungen (Caelestia: Toaster + Toasts.qml).
///
/// Regeln wie im Original:
/// - Neue kommen vorne dazu (`push_front`) und stehen unten, aeltere
///   rutschen nach oben.
/// - Sichtbar sind die ersten `maxVisible` (Caelestia `maxToasts` = 4). Die
///   aelteren bleiben in der Liste, ausgeblendet, und laufen trotzdem ab -
///   geht eine sichtbare, rueckt die naechste nach.
/// - Jede lebt 5 s. Caelestia hat zwar 7 s fuer Warnung und 10 s fuer
///   Fehler, aber nur fuer `timeout <= 0`; `Toaster.toast` hat 5000 als
///   Vorgabewert, und kein Aufrufer gibt etwas anderes mit. Gemessen am
///   Quelltext: diese Zweige laufen nie.
/// - Klick schliesst sofort.
public struct ToastQueue: Sendable {
    public static let maxVisible = 4
    public static let timeout: TimeInterval = 5

    /// Neueste zuerst.
    public private(set) var entries: [ToastEntry] = []
    private var nextID = 0

    public init() {}

    @discardableResult
    public mutating func push(title: String, message: String, symbol: String?, kind: ToastKind, now: Date) -> ToastEntry {
        let entry = ToastEntry(
            id: nextID,
            title: title,
            message: message,
            symbol: symbol ?? kind.defaultSymbol,
            kind: kind,
            deadline: now.addingTimeInterval(Self.timeout)
        )
        nextID += 1
        entries.insert(entry, at: 0)
        // Wer jetzt aus dem sichtbaren Bereich faellt, merkt sich das.
        for index in entries.indices.dropFirst(Self.maxVisible) {
            entries[index].hasBeenHidden = true
        }
        return entry
    }

    /// Klick: sofort weg. `false`, wenn es sie nicht (mehr) gibt.
    @discardableResult
    public mutating func dismiss(id: Int) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        entries.remove(at: index)
        return true
    }

    /// Alle abgelaufenen entfernen. `true`, wenn sich etwas geaendert hat.
    @discardableResult
    public mutating func expire(now: Date) -> Bool {
        let before = entries.count
        entries.removeAll { $0.deadline <= now }
        return entries.count != before
    }

    /// Wann die naechste ablaeuft - dafuer braucht es genau einen Timer.
    public var nextDeadline: Date? {
        entries.map(\.deadline).min()
    }

    /// Was zu sehen ist, neueste zuerst. Bei Vollbild nichts (Caelestia:
    /// `utilities.toasts.fullscreen` = "off").
    public func visible(fullscreen: Bool = false) -> [ToastEntry] {
        fullscreen ? [] : Array(entries.prefix(Self.maxVisible))
    }
}

/// Masse des Stapels (Caelestia: Toasts.qml, ToastItem.qml, Tokens).
public enum ToastLayout {
    /// Caelestia: toastWidth 430 minus 2 x padding.medium.
    public static let width: Double = 406
    /// Caelestia: spacing.small.
    public static let spacing: Double = 8
    /// Caelestia: padding.medium zum Rand bzw. zum Utilities-Panel.
    public static let margin: Double = 12
    /// Chip 40 + 2 x padding.small, siehe ToastCard.
    public static let itemHeight: Double = 56

    /// Hoehe von `count` Meldungen samt Abstaenden (Caelestia: implicitHeight
    /// startet bei -spacing).
    public static func stackHeight(count: Int, itemHeight: Double = itemHeight, spacing: Double = spacing) -> Double {
        guard count > 0 else { return 0 }
        return Double(count) * itemHeight + Double(count - 1) * spacing
    }
}

/// Die Texte der Kurzmeldungen, auf Deutsch (Caelestia-Originale im
/// Kommentar). Laufen als `String` bis zu `Text(entry.title)` im
/// Toast-Stapel (siehe Vertrag) - deshalb hier schon uebersetzt.
public enum ToastText {
    public struct Content: Equatable, Sendable {
        public let title: String
        public let message: String
        public let symbol: String
        public let kind: ToastKind

        public init(title: String, message: String, symbol: String, kind: ToastKind) {
            self.title = title
            self.message = message
            self.symbol = symbol
            self.kind = kind
        }
    }

    /// "Charger plugged in" / "Battery is charging".
    public static let chargerConnected = Content(
        title: String(localized: "Ladegerät angeschlossen"), message: String(localized: "Akku wird geladen"),
        symbol: "bolt.fill", kind: .info
    )

    /// "Charger unplugged" / "Battery is discharging".
    public static let chargerDisconnected = Content(
        title: String(localized: "Ladegerät getrennt"), message: String(localized: "Akku wird entladen"),
        symbol: "bolt.slash.fill", kind: .info
    )

    /// Caelestia: "Unknown device".
    public static let unknownDevice = String(localized: "Unbekanntes Gerät")

    /// "Audio output changed" / "Now using: %1".
    public static func audioOutput(_ name: String) -> Content {
        Content(title: String(localized: "Audioausgabe geändert"), message: String(localized: "Jetzt über \(deviceName(name))"),
                symbol: "speaker.wave.2.fill", kind: .info)
    }

    /// "Audio input changed" / "Now using: %1".
    public static func audioInput(_ name: String) -> Content {
        Content(title: String(localized: "Audioeingang geändert"), message: String(localized: "Jetzt über \(deviceName(name))"),
                symbol: "mic.fill", kind: .info)
    }

    static func deviceName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? unknownDevice : trimmed
    }
}

/// Meldet, wenn ein Standardgeraet (Ausgabe oder Eingang) wechselt
/// (Caelestia: services/Audio.qml). Wie dort nur, wenn es vorher schon einen
/// Namen gab und der neue anders heisst - der erste Wert beim Start zaehlt
/// nicht.
public struct ToastDeviceTracker: Sendable {
    public private(set) var name: String?

    public init(name: String? = nil) {
        self.name = name
    }

    /// `true`: Kurzmeldung zeigen.
    public mutating func update(name newName: String) -> Bool {
        let resolved = ToastText.deviceName(newName)
        defer { name = resolved }
        guard let name else { return false }
        return name != resolved
    }
}
