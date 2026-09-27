import Testing
import ApolloBase
@testable import ApolloConfig

@Suite("Eigene Filter aus der Config")
struct UserFilterTests {
    static func texts(_ source: String) -> (ConfigLoadResult, [CompiledValue]) {
        let result = LoaderHarness.load(["/config/shell.kdl": source])
        let values = result.ir?.surfaces.first?.children.compactMap { child -> CompiledValue? in
            guard case .element(let element) = child else { return nil }
            return element.arguments.first
        } ?? []
        return (result, values)
    }

    static func render(_ value: CompiledValue, globals: [String: Value] = [:], locals: [String: Value] = [:]) -> Value {
        let sink = WarningSink()
        return EvaluationHarness.evaluator(sink: sink).render(value.template, in: TestScope(locals: locals, globals: globals))
    }

    @Test("Filter mit value und Argumenten wird beim Laden eingesetzt, Abhängigkeiten stimmen")
    func expands() throws {
        let (result, values) = Self.texts("""
        var temp 20
        filter "fahrenheit" "{value * 9 / 5 + 32}"
        filter "between" args="lo hi" "{value >= lo && value <= hi}"
        filter "label" "{value | fahrenheit | round 1}"
        panel "p" anchor="left" {
            text "{var.temp | fahrenheit}"
            text "{var.temp | between 10 25}"
            text "{var.temp | label}"
            each t in="{[1, 2]}" { text "{t | fahrenheit}" }
        }
        """)
        #expect(result.diagnostics.filter { $0.severity == .error }.isEmpty, "\(result.diagnostics.map(\.message))")
        try #require(values.count == 3)
        let globals: [String: Value] = ["var": .record(Record([("temp", .number(20))]))]
        #expect(Self.render(values[0], globals: globals) == .number(68))
        #expect(Self.render(values[1], globals: globals) == .bool(true))
        #expect(Self.render(values[2], globals: globals) == .number(68))
        #expect(values[0].dependencies == [DependencyPath("var", ["temp"])])
    }

    @Test("Fehler zeigen auf die Deklaration oder die Aufrufstelle", arguments: [
        ("filter \"upper\" \"{value}\"", "'upper' is a built-in filter"),
        ("filter \"a\" \"{value}\"\nfilter \"a\" \"{value}\"", "duplicate filter 'a'"),
        ("filter \"Big\" \"{value}\"", "filter name 'Big' must be lowercase letters, digits and dashes"),
        ("filter \"a\" \"x{value}\"", "a filter body is one {…} expression"),
        ("filter \"a\" \"{item}\"", "unknown root 'item'"),
        ("filter \"a\" args=\"value\" \"{value}\"", "'value' cannot be an argument name"),
        ("filter \"a\" \"{value | a}\"", "unknown filter 'a'"),
        ("filter \"a\" args=\"n\" \"{value + n}\"\npanel \"p\" anchor=\"left\" { text \"{1 | a}\" }", "'a' expects 1 argument"),
        ("panel \"p\" anchor=\"left\" { text \"{1 | fahrenhiet}\" }\nfilter \"fahrenheit\" \"{value}\"", "unknown filter 'fahrenhiet'"),
    ])
    func errors(source: String, message: String) {
        let (result, _) = Self.texts(source)
        #expect(result.diagnostics.contains { $0.severity == .error && $0.message == message }, "\(result.diagnostics.map(\.message))")
    }
}
