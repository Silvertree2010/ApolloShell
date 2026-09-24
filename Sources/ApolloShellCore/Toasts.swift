import Foundation

public enum ToastKind: Sendable, Equatable {
    case info, success, warning, error

    public var iconID: String {
        switch self {
        case .info: "toast-info"
        case .success: "toast-success"
        case .warning: "toast-warning"
        case .error: "toast-error"
        }
    }

    public var defaultSymbol: String {
        switch self {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "exclamationmark.circle.fill"
        }
    }
}

public struct ToastEntry: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let message: String
    public let symbol: String
    public let kind: ToastKind
    public let deadline: Date
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

public struct ToastQueue: Sendable {
    public static let maxVisible = 4
    public static let timeout: TimeInterval = 5

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
        for index in entries.indices.dropFirst(Self.maxVisible) {
            entries[index].hasBeenHidden = true
        }
        return entry
    }

    @discardableResult
    public mutating func dismiss(id: Int) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        entries.remove(at: index)
        return true
    }

    @discardableResult
    public mutating func expire(now: Date) -> Bool {
        let before = entries.count
        entries.removeAll { $0.deadline <= now }
        return entries.count != before
    }

    public var nextDeadline: Date? {
        entries.map(\.deadline).min()
    }

    public func visible(fullscreen: Bool = false) -> [ToastEntry] {
        fullscreen ? [] : Array(entries.prefix(Self.maxVisible))
    }
}

public enum ToastLayout {
    public static let width: Double = 406
    public static let spacing: Double = 8
    public static let margin: Double = 12
    public static let itemHeight: Double = 56

    public static func stackHeight(count: Int, itemHeight: Double = itemHeight, spacing: Double = spacing) -> Double {
        guard count > 0 else { return 0 }
        return Double(count) * itemHeight + Double(count - 1) * spacing
    }
}

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

    public static let chargerConnected = Content(
        title: String(localized: "Charger Connected"), message: String(localized: "Battery is charging"),
        symbol: "bolt.fill", kind: .info
    )

    public static let chargerDisconnected = Content(
        title: String(localized: "Charger Unplugged"), message: String(localized: "Battery is discharging"),
        symbol: "bolt.slash.fill", kind: .info
    )

    public static let unknownDevice = String(localized: "Unknown Device")

    public static func audioOutput(_ name: String) -> Content {
        Content(title: String(localized: "Audio Output Changed"), message: String(localized: "Now using \(deviceName(name))"),
                symbol: "speaker.wave.2.fill", kind: .info)
    }

    public static func audioInput(_ name: String) -> Content {
        Content(title: String(localized: "Audio Input Changed"), message: String(localized: "Now using \(deviceName(name))"),
                symbol: "mic.fill", kind: .info)
    }

    static func deviceName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? unknownDevice : trimmed
    }
}

public struct ToastDeviceTracker: Sendable {
    public private(set) var name: String?

    public init(name: String? = nil) {
        self.name = name
    }

    public mutating func update(name newName: String) -> Bool {
        let resolved = ToastText.deviceName(newName)
        defer { name = resolved }
        guard let name else { return false }
        return name != resolved
    }
}
