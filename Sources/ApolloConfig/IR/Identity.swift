public struct Identity: Sendable, Hashable, CustomStringConvertible {
    public var components: [String]

    public init(_ components: [String]) {
        self.components = components
    }

    public func appending(_ component: String) -> Identity {
        var copy = components
        copy.append(component)
        return Identity(copy)
    }

    public var description: String {
        components.joined(separator: "/")
    }
}
