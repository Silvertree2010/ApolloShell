import ApolloBase

public indirect enum Expr: Sendable, Hashable {
    case literal(Value)
    case list([Expr])
    case path(root: String, members: [PathMember])
    case access(Expr, [PathMember])
    case unary(UnaryOperator, Expr)
    case binary(BinaryOperator, Expr, Expr)
    case conditional(Expr, Expr, Expr)
    case coalesce(Expr, Expr)
    case pipe(Expr, FilterCall)
}

public indirect enum PathMember: Sendable, Hashable {
    case field(String)
    case index(Expr)
}

public enum UnaryOperator: Sendable, Hashable { case not, negate }

public enum BinaryOperator: Sendable, Hashable {
    case or, and, equal, notEqual, less, lessOrEqual, greater, greaterOrEqual
    case add, subtract, multiply, divide, remainder
}

public struct FilterCall: Sendable, Hashable {
    public var name: String
    public var arguments: [Expr]
    public var span: SourceSpan

    public init(name: String, arguments: [Expr] = [], span: SourceSpan = .synthetic()) {
        self.name = name
        self.arguments = arguments
        self.span = span
    }
}

public enum TemplatePart: Sendable, Hashable {
    case text(String)
    case expression(Expr)
}

public enum StringTemplate: Sendable, Hashable {
    case literal(String)
    case whole(Expr)
    case parts([TemplatePart])
}

public struct DependencyPath: Sendable, Hashable {
    public var root: String
    public var fields: [String]

    public init(_ root: String, _ fields: [String] = []) {
        self.root = root
        self.fields = fields
    }
}
