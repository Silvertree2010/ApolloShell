import ApolloConfig

public struct DemandSet: Sendable, Equatable {
    public let paths: Set<[String]>

    public init(_ demanded: Set<DependencyPath> = []) {
        paths = Set(demanded.map(\.fields))
    }

    public var isEmpty: Bool { paths.isEmpty }

    public func wants(_ field: String) -> Bool {
        let parts = field.split(separator: ".").map(String.init)
        return paths.contains { path in
            Self.isPrefix(path, of: parts) || Self.isPrefix(parts, of: path)
        }
    }

    public func wantsAny(_ fields: [String]) -> Bool {
        fields.contains(where: wants)
    }

    private static func isPrefix(_ prefix: [String], of fields: [String]) -> Bool {
        prefix.count <= fields.count && Array(fields.prefix(prefix.count)) == prefix
    }
}
