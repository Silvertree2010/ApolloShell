import Testing
import Foundation
import ApolloBase
import ApolloConfig

private struct FixedScope: EvaluationScope {
    var locals: [String: Value]

    func local(_ name: String) -> Value? {
        locals[name]
    }

    func global(_ root: String, _ fields: [String]) -> Value {
        .null
    }
}

@Suite("Oeffentliche API fuer die Runtime")
struct PublicStateAPITests {
    static func compiled(_ text: String) -> CompiledValue {
        let span = SourceSpan.synthetic("test")
        guard case .success(let template) = ExpressionParser.parseTemplate(text, span: span) else {
            preconditionFailure(text)
        }
        return CompiledValue(template: template, dependencies: template.dependencies(locals: ["name"]), span: span)
    }

    @Test("ValueTemplate.evaluate ist von aussen aufrufbar")
    func valueTemplateEvaluateIsPublic() {
        let template = ValueTemplate.record([
            ValueTemplateField(name: "title", value: .scalar(Self.compiled("Hello {name}"))),
            ValueTemplateField(name: "items", value: .list([.scalar(Self.compiled("{1 + 1}"))])),
        ])
        let context = FilterContext(now: Date(timeIntervalSince1970: 0), locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(identifier: "UTC")!, services: DefaultFilterServices())
        let evaluator = Evaluator(filters: .builtin, context: { context }, warn: { _ in })
        let value = template.evaluate(with: evaluator, scope: FixedScope(locals: ["name": .string("Andrin")]))
        var expected = Record()
        expected["title"] = .string("Hello Andrin")
        expected["items"] = .list([.number(2)])
        #expect(value == .record(expected))
    }

    @Test("readAll liefert auch nicht mehr deklarierte Namen")
    func readAllKeepsUndeclaredNames() {
        let text = """
        old-name "kept"
        count 3
        cards {
            - "a"
            - "b"
        }
        count 4
        """
        let (values, diagnostics) = VarStateFile.readAll(text, file: "state.kdl")
        #expect(values["old-name"] == .string("kept"))
        #expect(values["count"] == .number(4))
        #expect(values["cards"] == .list([.string("a"), .string("b")]))
        #expect(diagnostics.map(\.message) == ["duplicate 'count' in state file, using the last one"])
        #expect(diagnostics.allSatisfy { $0.severity == .warning })
    }

    @Test("readAll meldet eine kaputte Datei wie read")
    func readAllReportsUnparsableFile() {
        let (values, diagnostics) = VarStateFile.readAll("count {", file: "state.kdl")
        #expect(values.isEmpty)
        #expect(diagnostics.map(\.kind) == [.stateFileUnreadable])
    }
}
