import Testing
import Foundation
@testable import ApolloConfig

@Suite("Filter runs")
struct RunFilterTests {
    static func entry(_ id: String, _ joins: Bool?) -> Value {
        var record = Record([("id", .string(id))])
        if let joins { record["joins"] = .bool(joins) }
        return .record(record)
    }

    @Test("A new run starts wherever the field is false or missing")
    func splits() {
        let items = [Self.entry("a", true), Self.entry("b", true), Self.entry("c", false), Self.entry("d", nil), Self.entry("e", true)]
        let runs = RunFilters.runs(items, field: "joins")
        #expect(runs.map { $0.count } == [2, 1, 2])
        #expect(runs[2] == [Self.entry("d", nil), Self.entry("e", true)])
        #expect(RunFilters.runs([], field: "joins").isEmpty)
    }

    @Test("Registered with one field argument and the runs feature")
    func registered() {
        let schema = SchemaRegistry.builtin.filters["runs"]
        #expect(schema?.arguments.map(\.name) == ["field"])
        #expect(schema?.feature == "runs")
        #expect(BuiltinFilters.entries["runs"] != nil)
    }
}
