import Foundation

enum ValueOrdering {
    static func rank(_ value: Value) -> Int {
        switch value {
        case .null: 0
        case .bool: 1
        case .number: 2
        case .string: 3
        case .date: 4
        case .list: 5
        case .record: 6
        case .image: 7
        }
    }

    static let localeAwareOptions: String.CompareOptions = [.caseInsensitive, .numeric, .widthInsensitive, .forcedOrdering]

    static func compare(_ lhs: Value, _ rhs: Value, locale: Locale) -> ComparisonResult {
        switch (lhs, rhs) {
        case (.bool(let a), .bool(let b)):
            return a == b ? .orderedSame : (a ? .orderedDescending : .orderedAscending)
        case (.number(let a), .number(let b)):
            return order(a, b)
        case (.string(let a), .string(let b)):
            return a.compare(b, options: localeAwareOptions, range: nil, locale: locale)
        case (.date(let a), .date(let b)):
            return order(a, b)
        default:
            return order(rank(lhs), rank(rhs))
        }
    }

    static func order<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }

    static func field(_ name: String, of value: Value) -> Value {
        guard case .record(let record) = value else { return .null }
        return record[name] ?? .null
    }
}
