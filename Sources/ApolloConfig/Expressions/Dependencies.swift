import ApolloBase

extension Expr {
    public func dependencies(locals: Set<String>) -> Set<DependencyPath> {
        StackHeadroom.run {
            var result = Set<DependencyPath>()
            self.collectDependencies(locals: locals, into: &result)
            return result
        }
    }

    func collectDependencies(locals: Set<String>, into result: inout Set<DependencyPath>) {
        switch self {
        case .literal:
            break
        case .list(let items):
            for item in items {
                item.collectDependencies(locals: locals, into: &result)
            }
        case .path(let root, let members):
            if !locals.contains(root) {
                var fields: [String] = []
                for member in members {
                    guard case .field(let name) = member else { break }
                    fields.append(name)
                }
                result.insert(DependencyPath(root, fields))
            }
            Self.collectIndexDependencies(members, locals: locals, into: &result)
        case .access(let base, let members):
            base.collectDependencies(locals: locals, into: &result)
            Self.collectIndexDependencies(members, locals: locals, into: &result)
        case .unary(_, let operand):
            operand.collectDependencies(locals: locals, into: &result)
        case .binary(_, let lhs, let rhs), .coalesce(let lhs, let rhs):
            lhs.collectDependencies(locals: locals, into: &result)
            rhs.collectDependencies(locals: locals, into: &result)
        case .conditional(let condition, let then, let otherwise):
            condition.collectDependencies(locals: locals, into: &result)
            then.collectDependencies(locals: locals, into: &result)
            otherwise.collectDependencies(locals: locals, into: &result)
        case .pipe(let input, let call):
            input.collectDependencies(locals: locals, into: &result)
            for argument in call.arguments {
                argument.collectDependencies(locals: locals, into: &result)
            }
            if call.name == "relative" {
                result.insert(DependencyPath("clock", ["now"]))
            }
        }
    }

    static func collectIndexDependencies(_ members: [PathMember], locals: Set<String>, into result: inout Set<DependencyPath>) {
        for member in members {
            if case .index(let index) = member {
                index.collectDependencies(locals: locals, into: &result)
            }
        }
    }
}

extension StringTemplate {
    public func dependencies(locals: Set<String>) -> Set<DependencyPath> {
        StackHeadroom.run {
            switch self {
            case .literal:
                return []
            case .whole(let expr):
                return expr.dependencies(locals: locals)
            case .parts(let parts):
                var result = Set<DependencyPath>()
                for part in parts {
                    if case .expression(let expr) = part {
                        expr.collectDependencies(locals: locals, into: &result)
                    }
                }
                return result
            }
        }
    }

    public var isConstant: Bool {
        dependencies(locals: []).isEmpty
    }
}
