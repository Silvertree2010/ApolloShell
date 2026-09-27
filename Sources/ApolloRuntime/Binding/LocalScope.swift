import ApolloConfig

public struct LocalScope: Sendable, Hashable {
    private static let maximumLayers = 8

    private final class Layer: Sendable {
        let name: String
        let value: Value
        let parent: Layer?
        let depth: Int

        init(_ name: String, _ value: Value, parent: Layer?) {
            self.name = name
            self.value = value
            self.parent = parent
            depth = (parent?.depth ?? 0) + 1
        }
    }

    private var values: [String: Value]
    private var layer: Layer?

    public init(_ values: [String: Value] = [:]) {
        self.values = values
    }

    public func adding(_ name: String, _ value: Value) -> LocalScope {
        var copy = self
        if let layer, layer.depth >= Self.maximumLayers {
            copy = LocalScope(flattened)
        }
        copy.layer = Layer(name, value, parent: copy.layer)
        return copy
    }

    public subscript(name: String) -> Value? {
        var current = layer
        while let node = current {
            if node.name == name { return node.value }
            current = node.parent
        }
        return values[name]
    }

    private var flattened: [String: Value] {
        guard layer != nil else { return values }
        var result = values
        var pending: [Layer] = []
        var current = layer
        while let node = current {
            pending.append(node)
            current = node.parent
        }
        for node in pending.reversed() {
            result[node.name] = node.value
        }
        return result
    }

    public static func == (lhs: LocalScope, rhs: LocalScope) -> Bool {
        if lhs.layer === rhs.layer && lhs.values == rhs.values { return true }
        return lhs.flattened == rhs.flattened
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(flattened)
    }
}

enum ContextScopeKeys {
    static let selfIdentity = "$self"
    static let surfaceKey = "$surface"
    static let screenKey = "$screen"
}
