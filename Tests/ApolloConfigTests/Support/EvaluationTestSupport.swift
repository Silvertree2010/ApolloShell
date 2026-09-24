import Foundation
import Synchronization
import ApolloBase
@testable import ApolloConfig

struct TestScope: EvaluationScope {
    var locals: [String: Value] = [:]
    var globals: [String: Value] = [:]

    func local(_ name: String) -> Value? {
        locals[name]
    }

    func global(_ root: String, _ fields: [String]) -> Value {
        var current = globals[root] ?? .null
        for field in fields {
            guard case .record(let record) = current else { return .null }
            current = record[field] ?? .null
        }
        return current
    }
}

final class RecordingScope: EvaluationScope {
    var calls: [DependencyPath] = []

    func local(_ name: String) -> Value? {
        nil
    }

    func global(_ root: String, _ fields: [String]) -> Value {
        calls.append(DependencyPath(root, fields))
        return .list([.number(7)])
    }
}

final class WarningSink: Sendable {
    private let stored = Mutex<[Diagnostic]>([])

    var diagnostics: [Diagnostic] {
        stored.withLock { $0 }
    }

    func add(_ diagnostic: Diagnostic) {
        stored.withLock { $0.append(diagnostic) }
    }
}

enum EvaluationHarness {
    static func evaluator(filters: FilterTable = .builtin, sink: WarningSink, context: FilterContext = FilterHarness.context) -> Evaluator {
        Evaluator(filters: filters, context: { context }, warn: { sink.add($0) })
    }

    static func expression(_ source: String) throws -> Expr {
        try ExpressionParser.parseExpression(source, span: .synthetic("test")).get()
    }
}
