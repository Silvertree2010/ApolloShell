import ApolloConfig

public enum ProviderActionError: Error, Sendable, Equatable, CustomStringConvertible {
    case unknownAction(String)
    case invalidArgument(action: String, message: String)
    case unavailable(action: String, reason: String)

    public var description: String {
        switch self {
        case .unknownAction(let action): "unknown action \"\(action)\""
        case .invalidArgument(let action, let message): "\(action): \(message)"
        case .unavailable(let action, let reason): "\(action) is unavailable: \(reason)"
        }
    }
}

public struct ActionArguments: Sendable {
    public let action: String
    public let values: [Value]
    public let properties: Record

    public init(_ action: String, _ values: [Value], _ properties: Record = Record()) {
        self.action = action
        self.values = values
        self.properties = properties
    }

    public func property(_ name: String) -> Value? {
        properties[name]
    }

    public func value(_ index: Int) throws(ProviderActionError) -> Value {
        guard values.indices.contains(index) else {
            throw .invalidArgument(action: action, message: "missing argument \(index + 1)")
        }
        return values[index]
    }

    public func number(_ index: Int, range: ClosedRange<Double>? = nil) throws(ProviderActionError) -> Double {
        guard case .number(let number) = try value(index), number.isFinite else {
            throw .invalidArgument(action: action, message: "argument \(index + 1) must be a number")
        }
        if let range, !range.contains(number) {
            throw .invalidArgument(action: action, message: "argument \(index + 1) must be between \(range.lowerBound) and \(range.upperBound)")
        }
        return number
    }

    public func bool(_ index: Int) throws(ProviderActionError) -> Bool {
        guard case .bool(let flag) = try value(index) else {
            throw .invalidArgument(action: action, message: "argument \(index + 1) must be a bool")
        }
        return flag
    }

    public func string(_ index: Int) throws(ProviderActionError) -> String {
        switch try value(index) {
        case .string(let text): return text
        case .number(let number) where number.isFinite: return number.rounded() == number && abs(number) < 1e15 ? String(Int64(number)) : String(number)
        default: throw .invalidArgument(action: action, message: "argument \(index + 1) must be a string")
        }
    }
}
