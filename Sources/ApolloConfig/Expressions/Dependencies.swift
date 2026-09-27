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

    func collectPathRoots(into result: inout Set<String>) {
        switch self {
        case .literal:
            break
        case .list(let items):
            for item in items {
                item.collectPathRoots(into: &result)
            }
        case .path(let root, let members):
            result.insert(root)
            Self.collectIndexRoots(members, into: &result)
        case .access(let base, let members):
            base.collectPathRoots(into: &result)
            Self.collectIndexRoots(members, into: &result)
        case .unary(_, let operand):
            operand.collectPathRoots(into: &result)
        case .binary(_, let lhs, let rhs), .coalesce(let lhs, let rhs):
            lhs.collectPathRoots(into: &result)
            rhs.collectPathRoots(into: &result)
        case .conditional(let condition, let then, let otherwise):
            condition.collectPathRoots(into: &result)
            then.collectPathRoots(into: &result)
            otherwise.collectPathRoots(into: &result)
        case .pipe(let input, let call):
            input.collectPathRoots(into: &result)
            for argument in call.arguments {
                argument.collectPathRoots(into: &result)
            }
        }
    }

    static func collectIndexRoots(_ members: [PathMember], into result: inout Set<String>) {
        for member in members {
            if case .index(let index) = member {
                index.collectPathRoots(into: &result)
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

    public var pathRoots: Set<String> {
        StackHeadroom.run {
            var result = Set<String>()
            switch self {
            case .literal:
                break
            case .whole(let expr):
                expr.collectPathRoots(into: &result)
            case .parts(let parts):
                for part in parts {
                    if case .expression(let expr) = part {
                        expr.collectPathRoots(into: &result)
                    }
                }
            }
            return result
        }
    }
}
