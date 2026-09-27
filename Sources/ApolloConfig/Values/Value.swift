import Foundation

public struct ImageRef: Sendable, Hashable {
    public var source: String
    public var id: String

    public init(source: String, id: String) {
        self.source = source
        self.id = id
    }
}

public struct Record: Sendable, Hashable {
    private var orderedKeys: [String]
    private var storage: [String: Value]

    public init(_ pairs: [(String, Value)] = []) {
        orderedKeys = []
        storage = [:]
        for (key, value) in pairs {
            self[key] = value
        }
    }

    public var keys: [String] { orderedKeys }

    public var count: Int { orderedKeys.count }

    var values: [Value] { orderedKeys.compactMap { storage[$0] } }

    public subscript(key: String) -> Value? {
        get { storage[key] }
        set {
            guard let newValue else {
                if storage.removeValue(forKey: key) != nil {
                    orderedKeys.removeAll { $0 == key }
                }
                return
            }
            if storage.updateValue(newValue, forKey: key) == nil {
                orderedKeys.append(key)
            }
        }
    }

    public static func == (lhs: Record, rhs: Record) -> Bool {
        lhs.storage == rhs.storage
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storage)
    }
}

extension Value {
    public func isEqualInOrder(_ other: Value) -> Bool {
        switch (self, other) {
        case (.record(let left), .record(let right)):
            return left.keys == right.keys && zip(left.values, right.values).allSatisfy { $0.isEqualInOrder($1) }
        case (.list(let left), .list(let right)):
            return left.count == right.count && zip(left, right).allSatisfy { $0.isEqualInOrder($1) }
        default:
            return self == other
        }
    }
}

public enum Value: Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case list([Value])
    case record(Record)
    case date(Date)
    case image(ImageRef)

    public var isTruthy: Bool {
        switch self {
        case .null: false
        case .bool(let flag): flag
        case .number(let number): number != 0 && !number.isNaN
        case .string(let text): !text.isEmpty
        case .list(let items): !items.isEmpty
        case .record, .date, .image: true
        }
    }

    public var typeName: String {
        switch self {
        case .null: "null"
        case .bool: "bool"
        case .number: "number"
        case .string: "string"
        case .list: "list"
        case .record: "record"
        case .date: "date"
        case .image: "image"
        }
    }
}
