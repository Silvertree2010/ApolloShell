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

    @Test("Filter, die sich beim Einsetzen aufblähen, werden beim Laden abgelehnt statt hängen zu bleiben")
    func expansionIsBounded() {
        var source = "filter \"f1\" \"{value + value}\"\n"
        for level in 2...12 {
            source += "filter \"f\(level)\" \"{value | f\(level - 1) | f\(level - 1)}\"\n"
        }
        source += "panel \"p\" anchor=\"left\" { text \"{1 | f12}\" }\n"
        let (result, _) = Self.texts(source)
        #expect(result.diagnostics.contains { $0.severity == .error && $0.message.contains("grows past 4096 parts") })
        let chained = "filter \"d\" \"{value + value}\"\npanel \"p\" anchor=\"left\" { text \"{1\(String(repeating: " | d", count: 30))}\" }\n"
        #expect(Self.texts(chained).0.diagnostics.contains { $0.message.contains("grows past 4096 parts") })
    }

    @Test("Eigene Filter wirken auch in var-Vorgaben und from=")
    func varsUseFilters() throws {
        let result = LoaderHarness.load(["/config/shell.kdl": """
        filter "dbl" "{value * 2}"
        var a 5
        var b from="{var.a | dbl}"
        var c "{3 | dbl}"
        """])
        let vars = try #require(result.ir?.vars)
        let b = try #require(vars.first { $0.name == "b" }?.derived)
        let c = try #require(vars.first { $0.name == "c" }?.defaultValue)
        #expect(Self.render(b, globals: ["var": .record(Record([("a", .number(5))]))]) == .number(10))
        guard case .scalar(let compiled) = c else { Issue.record("no scalar"); return }
        #expect(Self.render(compiled) == .number(6))
    }

    @Test("let mit unbekanntem Filter ist ein Fehler statt still null")
    func letNeedsBuiltinFilters() {
        let (result, _) = Self.texts("filter \"dbl\" \"{value * 2}\"\nlet x=\"{5 | dbl}\"\nlet y=\"{'a' | upperr}\"\n")
        let errors = result.diagnostics.filter { $0.severity == .error }.map(\.message)
        #expect(errors.contains("unknown filter 'dbl' in 'let'"))
        #expect(errors.contains("unknown filter 'upperr' in 'let'"))
    }

    @Test("filter mit Kindern ist ein Fehler")
    func noChildren() {
        let (result, _) = Self.texts("filter \"dbl\" \"{value * 2}\" { text \"junk\" }\n")
        #expect(result.diagnostics.contains { $0.message == "filter has no children" })
    }
}
