import Foundation
import ApolloBase
import ApolloConfig
@testable import ApolloRuntime

enum RuntimeIR {
    static let file = "/config/shell.kdl"

    static func span(_ line: Int, column: Int = 1) -> SourceSpan {
        SourceSpan(file: file, start: SourcePosition(offset: line * 100 + column, line: line, column: column), end: SourcePosition(offset: line * 100 + column + 1, line: line, column: column + 1))
    }

    static func value(_ text: String, locals: Set<String> = [], line: Int = 1) -> CompiledValue {
        let at = span(line)
        let template = try! ExpressionParser.parseTemplate(text, span: at).get()
        return CompiledValue(template: template, dependencies: template.dependencies(locals: locals), span: at)
    }

    static func literal(_ constant: Value, line: Int = 1) -> CompiledValue {
        CompiledValue(template: .whole(.literal(constant)), dependencies: [], span: span(line))
    }

    static func string(_ text: String, line: Int = 1) -> CompiledValue {
        literal(.string(text), line: line)
    }

    static func number(_ number: Double, line: Int = 1) -> CompiledValue {
        literal(.number(number), line: line)
    }

    static func call(_ name: String, _ arguments: [CompiledValue] = [], properties: [String: CompiledValue] = [:], children: [ValueTemplate] = [], line: Int = 1) -> ActionIR {
        .call(ActionCallIR(name: name, arguments: arguments, properties: properties, children: children, span: span(line)))
    }

    static func log(_ text: String, locals: Set<String> = [], line: Int = 1) -> ActionIR {
        call("log", [value(text, locals: locals, line: line)], line: line)
    }

    static func plainVar(_ name: String, _ type: ValueType, _ defaultValue: Value, persist: Bool = false) -> VarDecl {
        VarDecl(name: name, type: type, defaultValue: .scalar(literal(defaultValue)), persist: persist, derived: nil, span: span(90))
    }

    static func derivedVar(_ name: String, _ type: ValueType, from text: String) -> VarDecl {
        VarDecl(name: name, type: type, defaultValue: .scalar(literal(.null)), persist: false, derived: value(text, line: 91), span: span(91))
    }
}

@MainActor
func settle(_ rounds: Int = 50) async {
    for _ in 0..<rounds {
        await Task.yield()
    }
}

@MainActor
final class Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
