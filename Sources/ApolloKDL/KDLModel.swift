import ApolloBase

public enum KDLScalar: Sendable, Hashable {
    case string(String)
    case number(Double, raw: String)
    case bool(Bool)
    case null
}

public struct KDLValue: Sendable, Hashable {
    public var scalar: KDLScalar
    public var annotation: String?
    public var span: SourceSpan

    public init(_ scalar: KDLScalar, annotation: String? = nil, span: SourceSpan = .synthetic()) {
        self.scalar = scalar
        self.annotation = annotation
        self.span = span
    }
}

public struct KDLProperty: Sendable, Hashable {
    public var name: String
    public var value: KDLValue
    public var span: SourceSpan

    public init(name: String, value: KDLValue, span: SourceSpan = .synthetic()) {
        self.name = name
        self.value = value
        self.span = span
    }
}

public struct KDLNode: Sendable, Hashable {
    public var name: String
    public var annotation: String?
    public var arguments: [KDLValue]
    public var properties: [KDLProperty]
    public var children: [KDLNode]?
    public var span: SourceSpan
    public var nameSpan: SourceSpan
    public var lineRange: Range<Int>
    var childrenBlock: Range<Int>?

    public init(name: String, arguments: [KDLValue] = [], properties: [KDLProperty] = [], children: [KDLNode]? = nil) {
        self.name = name
        self.annotation = nil
        self.arguments = arguments
        self.properties = properties
        self.children = children
        self.span = .synthetic()
        self.nameSpan = .synthetic()
        self.lineRange = 0..<0
        self.childrenBlock = nil
    }

    public func property(_ name: String) -> KDLProperty? {
        properties.last { $0.name == name }
    }
}

public struct KDLDocument: Sendable {
    public var file: String
    public var text: String
    public var nodes: [KDLNode]
}

public struct KDLParseError: Error, Sendable, Hashable {
    public var message: String
    public var span: SourceSpan

    public init(message: String, span: SourceSpan) {
        self.message = message
        self.span = span
    }
}

public typealias KDLNodePath = [Int]

public struct KDLEditError: Error, Sendable, Hashable {
    public var message: String

    public init(message: String) {
        self.message = message
    }
}
