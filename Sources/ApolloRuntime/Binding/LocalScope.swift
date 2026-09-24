import ApolloConfig

public struct LocalScope: Sendable, Hashable {
    private var values: [String: Value]

    public init(_ values: [String: Value] = [:]) {
        self.values = values
    }

    public func adding(_ name: String, _ value: Value) -> LocalScope {
        var copy = values
        copy[name] = value
        return LocalScope(copy)
    }

    public subscript(name: String) -> Value? {
        values[name]
    }
}

enum ContextScopeKeys {
    static let selfIdentity = "$self"
    static let surfaceKey = "$surface"
    static let screenKey = "$screen"
}
