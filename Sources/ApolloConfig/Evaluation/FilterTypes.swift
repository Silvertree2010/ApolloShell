import Foundation

public protocol FilterServices: Sendable {
    func appSearch(_ apps: [Value], query: String) -> [Value]
    func monthGrid(_ date: Date, offset: Int, firstWeekday: String) -> Value
    func uptimeText(_ seconds: Double) -> String
    func normalizedURL(_ text: String) -> String?
    func symbolExists(_ name: String) -> Bool
    func chordDisplay(_ chord: String) -> String
    func hotkeyWarning(_ chord: String) -> String?
    func temperatureText(_ celsius: Double) -> String
}

public struct FilterContext: Sendable {
    public var now: Date
    public var locale: Locale
    public var timeZone: TimeZone
    public var services: any FilterServices

    public init(now: Date, locale: Locale, timeZone: TimeZone, services: any FilterServices) {
        self.now = now
        self.locale = locale
        self.timeZone = timeZone
        self.services = services
    }
}

public typealias FilterFunction = @Sendable (Value, [Value], FilterContext) -> FilterResult

public enum FilterResult: Sendable, Hashable {
    case value(Value)
    case failure(String)
}

public struct FilterArity: Sendable, Hashable {
    public var minimum: Int
    public var maximum: Int

    public init(_ minimum: Int, _ maximum: Int) {
        self.minimum = minimum
        self.maximum = maximum
    }

    public func accepts(_ count: Int) -> Bool {
        count >= minimum && count <= maximum
    }

    var phrase: String {
        if minimum == maximum {
            return "\(minimum) \(minimum == 1 ? "argument" : "arguments")"
        }
        return "\(minimum) to \(maximum) arguments"
    }
}

public struct FilterTable: Sendable {
    struct Entry: Sendable {
        let function: FilterFunction
        let arity: FilterArity?
    }

    private var entries: [String: Entry]

    init(entries: [String: Entry]) {
        self.entries = entries
    }

    public static let builtin = FilterTable(entries: BuiltinFilters.entries)

    public func function(named name: String) -> FilterFunction? {
        entries[name]?.function
    }

    public func arity(named name: String) -> FilterArity? {
        entries[name]?.arity
    }

    public var names: [String] {
        entries.keys.sorted()
    }

    public func adding(_ name: String, _ function: @escaping FilterFunction) -> FilterTable {
        var copy = self
        copy.entries[name] = Entry(function: function, arity: nil)
        return copy
    }
}
