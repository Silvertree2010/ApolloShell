import Foundation

/// The kind of a toast (Caelestia: Toast.Type). Decides the color and the
/// symbol when the caller brings none.
public enum ToastKind: Sendable, Equatable {
    case info, success, warning, error

    /// The id for the symbol swap in the theme (`icons/<id>.png`).
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

/// One toast in the queue.
public struct ToastEntry: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let message: String
    public let symbol: String
    public let kind: ToastKind
    /// From here on it closes itself.
    public let deadline: Date
    /// It was hidden once because there were too many. When it moves up later,
    /// it only fades in (0.7 -> 1) as in Caelestia instead of coming out of
    /// nothing - the transition of the user interface hangs on that.
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

/// The queue of the toasts (Caelestia: Toaster + Toasts.qml).
///
/// The rules as in the original:
/// - New ones come in at the front (`push_front`) and stand at the bottom,
///   older ones slide up.
/// - Visible are the first `maxVisible` (Caelestia `maxToasts` = 4). The older
///   ones stay in the list, hidden, and run out all the same - when a visible
///   one goes, the next one moves up.
/// - Every one lives 5 s. Caelestia does have 7 s for a warning and 10 s for
///   an error, but only for `timeout <= 0`; `Toaster.toast` has 5000 as its
///   default value, and no caller brings anything else. Measured against the
///   source: those branches never run.
/// - A click closes it right away.
public struct ToastQueue: Sendable {
    public static let maxVisible = 4
    public static let timeout: TimeInterval = 5

    /// The newest first.
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
        // Whoever falls out of the visible area now remembers that.
        for index in entries.indices.dropFirst(Self.maxVisible) {
            entries[index].hasBeenHidden = true
        }
        return entry
    }

    /// A click: away right away. `false` when it does not (or no longer) exist.
    @discardableResult
    public mutating func dismiss(id: Int) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        entries.remove(at: index)
        return true
    }

    /// Remove everything that has run out. `true` when something changed.
    @discardableResult
    public mutating func expire(now: Date) -> Bool {
        let before = entries.count
        entries.removeAll { $0.deadline <= now }
        return entries.count != before
    }

    /// When the next one runs out - exactly one timer is needed for that.
    public var nextDeadline: Date? {
        entries.map(\.deadline).min()
    }

    /// What can be seen, the newest first. In full screen nothing (Caelestia:
    /// `utilities.toasts.fullscreen` = "off").
    public func visible(fullscreen: Bool = false) -> [ToastEntry] {
        fullscreen ? [] : Array(entries.prefix(Self.maxVisible))
    }
}

/// The measurements of the stack (Caelestia: Toasts.qml, ToastItem.qml, Tokens).
public enum ToastLayout {
    /// Caelestia: toastWidth 430 minus 2 x padding.medium.
    public static let width: Double = 406
    /// Caelestia: spacing.small.
    public static let spacing: Double = 8
    /// Caelestia: padding.medium to the edge or to the utilities panel.
    public static let margin: Double = 12
    /// The chip 40 + 2 x padding.small, see ToastCard.
    public static let itemHeight: Double = 56

    /// The height of `count` toasts including the gaps (Caelestia:
    /// implicitHeight starts at -spacing).
    public static func stackHeight(count: Int, itemHeight: Double = itemHeight, spacing: Double = spacing) -> Double {
        guard count > 0 else { return 0 }
        return Double(count) * itemHeight + Double(count - 1) * spacing
    }
}

/// The texts of the toasts (the Caelestia originals in the comment). They run
/// as a `String` all the way to `Text(entry.title)` in the toast stack (see
/// the contract).
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
        title: String(localized: "Charger Connected"), message: String(localized: "Battery is charging"),
        symbol: "bolt.fill", kind: .info
    )

    /// "Charger unplugged" / "Battery is discharging".
    public static let chargerDisconnected = Content(
        title: String(localized: "Charger Unplugged"), message: String(localized: "Battery is discharging"),
        symbol: "bolt.slash.fill", kind: .info
    )

    /// Caelestia: "Unknown device".
    public static let unknownDevice = String(localized: "Unknown Device")

    /// "Audio output changed" / "Now using: %1".
    public static func audioOutput(_ name: String) -> Content {
        Content(title: String(localized: "Audio Output Changed"), message: String(localized: "Now using \(deviceName(name))"),
                symbol: "speaker.wave.2.fill", kind: .info)
    }

    /// "Audio input changed" / "Now using: %1".
    public static func audioInput(_ name: String) -> Content {
        Content(title: String(localized: "Audio Input Changed"), message: String(localized: "Now using \(deviceName(name))"),
                symbol: "mic.fill", kind: .info)
    }

    static func deviceName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? unknownDevice : trimmed
    }
}

/// Reports when a default device (output or input) changes (Caelestia:
/// services/Audio.qml). As there, only when there was a name before and the
/// new one is different - the first value on the start does not count.
public struct ToastDeviceTracker: Sendable {
    public private(set) var name: String?

    public init(name: String? = nil) {
        self.name = name
    }

    /// `true`: show a toast.
    public mutating func update(name newName: String) -> Bool {
        let resolved = ToastText.deviceName(newName)
        defer { name = resolved }
        guard let name else { return false }
        return name != resolved
    }
}
