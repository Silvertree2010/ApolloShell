public struct Identity: Sendable, Hashable, CustomStringConvertible {
    public var components: [String]

    public init(_ components: [String]) {
        self.components = components
    }

    public func appending(_ component: String) -> Identity {
        Identity(components + [component])
    }

    public var description: String {
        components.joined(separator: "/")
    }
}
