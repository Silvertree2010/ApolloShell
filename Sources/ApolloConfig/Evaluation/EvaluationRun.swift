import Foundation
import ApolloBase

struct EvaluationRun {
    let evaluator: Evaluator
    let scope: any EvaluationScope
    let span: SourceSpan?

    func render(_ template: StringTemplate) -> Value {
        switch template {
        case .literal(let text):
            return .string(text)
        case .whole(let expr):
            return value(expr)
        case .parts(let parts):
            var text = ""
            for part in parts {
                switch part {
                case .text(let literal): text += literal
                case .expression(let expr): text += value(expr).stringified
                }
            }
            return .string(text)
        }
    }

    func value(_ expr: Expr) -> Value {
        switch expr {
        case .literal(let literal):
            return literal
        case .list(let items):
            return .list(items.map { value($0) })
        case .path(let root, let members):
            return path(root, members)
        case .access(let base, let members):
            return apply(members[...], to: value(base))
        case .unary(let op, let operand):
            return unary(op, value(operand))
        case .binary(let op, let lhs, let rhs):
            return binary(op, lhs, rhs)
        case .conditional(let condition, let then, let otherwise):
            return value(condition).isTruthy ? value(then) : value(otherwise)
        case .coalesce(let lhs, let rhs):
            let left = value(lhs)
            if case .null = left {
                return value(rhs)
            }
            return left
        case .pipe(let input, let call):
            return pipe(value(input), call)
        }
    }

    func path(_ root: String, _ members: [PathMember]) -> Value {
        if let local = scope.local(root) {
            return apply(members[...], to: local)
        }
        var fields: [String] = []
        var rest = members[...]
        while let first = rest.first, case .field(let name) = first {
            fields.append(name)
            rest = rest.dropFirst()
        }
        return apply(rest, to: scope.global(root, fields))
    }

    func apply(_ members: ArraySlice<PathMember>, to start: Value) -> Value {
        var current = start
        for member in members {
            if case .null = current {
                return .null
            }
            current = self.member(member, of: current)
        }
        return current
    }

    func member(_ member: PathMember, of base: Value) -> Value {
        switch member {
        case .field(let name):
            guard case .record(let record) = base else {
                report("a \(base.typeName) has no field '\(name)'")
                return .null
            }
            return record[name] ?? .null
        case .index(let indexExpr):
            let index = value(indexExpr)
            switch (base, index) {
            case (_, .null):
                return .null
            case (.list(let items), .number(let number)):
                guard let position = ValueIndexing.wholeNumber(number) else {
                    report(Self.indexIssueMessage("list", ValueIndexing.classify(number)))
                    return .null
                }
                return ValueIndexing.element(items, position) ?? .null
            case (.string(let text), .number(let number)):
                guard let position = ValueIndexing.wholeNumber(number) else {
                    report(Self.indexIssueMessage("string", ValueIndexing.classify(number)))
                    return .null
                }
                return ValueIndexing.element(Array(text), position).map { .string(String($0)) } ?? .null
            case (.record(let record), .string(let key)):
                return record[key] ?? .null
            default:
                report("cannot index a \(base.typeName) with a \(index.typeName)")
                return .null
            }
        }
    }

    func unary(_ op: UnaryOperator, _ operand: Value) -> Value {
        switch op {
        case .not:
            return .bool(!operand.isTruthy)
        case .negate:
            switch operand {
            case .null:
                return .null
            case .number(let number):
                return .number(-number)
            default:
                report("cannot negate a \(operand.typeName)")
                return .null
            }
        }
    }

    func binary(_ op: BinaryOperator, _ lhs: Expr, _ rhs: Expr) -> Value {
        switch op {
        case .and:
            return .bool(value(lhs).isTruthy && value(rhs).isTruthy)
        case .or:
            return .bool(value(lhs).isTruthy || value(rhs).isTruthy)
        default:
            break
        }
        let left = value(lhs)
        let right = value(rhs)
        switch op {
        case .equal:
            return .bool(left == right)
        case .notEqual:
            return .bool(left != right)
        case .less, .lessOrEqual, .greater, .greaterOrEqual:
            return compare(op, left, right)
        case .add:
            return add(left, right)
        default:
            return arithmetic(op, left, right)
        }
    }

    func compare(_ op: BinaryOperator, _ left: Value, _ right: Value) -> Value {
        let order: ComparisonResult
        switch (left, right) {
        case (.null, _), (_, .null):
            return .null
        case (.number(let a), .number(let b)):
            order = Self.order(a, b)
        case (.string(let a), .string(let b)):
            order = Self.order(a, b)
        case (.date(let a), .date(let b)):
            order = Self.order(a, b)
        default:
            report("cannot compare a \(left.typeName) with a \(right.typeName)")
            return .null
        }
        switch op {
        case .less: return .bool(order == .orderedAscending)
        case .lessOrEqual: return .bool(order != .orderedDescending)
        case .greater: return .bool(order == .orderedDescending)
        default: return .bool(order != .orderedAscending)
        }
    }

    static func order<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }

    func add(_ left: Value, _ right: Value) -> Value {
        switch (left, right) {
        case (.string, _), (_, .string):
            return .string(left.stringified + right.stringified)
        case (.null, _), (_, .null):
            return .null
        case (.number(let a), .number(let b)):
            return Self.finite(a + b)
        default:
            report("cannot add a \(left.typeName) and a \(right.typeName)")
            return .null
        }
    }

    func arithmetic(_ op: BinaryOperator, _ left: Value, _ right: Value) -> Value {
        switch (left, right) {
        case (.null, _), (_, .null):
            return .null
        case (.number(let a), .number(let b)):
            switch op {
            case .subtract: return Self.finite(a - b)
            case .multiply: return Self.finite(a * b)
            case .divide: return b == 0 ? .null : Self.finite(a / b)
            default: return b == 0 ? .null : Self.finite(a.truncatingRemainder(dividingBy: b))
            }
        default:
            report("cannot apply '\(Self.symbol(op))' to a \(left.typeName) and a \(right.typeName)")
            return .null
        }
    }

    static func symbol(_ op: BinaryOperator) -> String {
        switch op {
        case .subtract: "-"
        case .multiply: "*"
        case .divide: "/"
        default: "%"
        }
    }

    static func finite(_ number: Double) -> Value {
        number.isFinite ? .number(number) : .null
    }

    func pipe(_ input: Value, _ call: FilterCall) -> Value {
        let arguments = call.arguments.map { value($0) }
        guard let function = evaluator.filters.function(named: call.name) else {
            evaluator.report("unknown filter '\(call.name)'", span: call.span)
            return .null
        }
        switch function(input, arguments, evaluator.context()) {
        case .value(let result):
            return result
        case .failure(let message):
            evaluator.report(message, span: call.span)
            return .null
        }
    }

    func report(_ message: String) {
        evaluator.report(message, span: span)
    }

    static func indexIssueMessage(_ kind: String, _ issue: ValueIndexIssue) -> String {
        switch issue {
        case .notWhole: "a \(kind) index must be a whole number"
        case .outOfRange: "a \(kind) index is out of range"
        }
    }
}
