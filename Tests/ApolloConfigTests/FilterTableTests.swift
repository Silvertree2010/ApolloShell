import Testing
import Foundation
@testable import ApolloConfig

@Suite("Filtertabelle und Filter-Grundlagen")
struct FilterTableTests {
    static let probe = BuiltinFilter("probe", arity: FilterArity(1, 2)) { input, arguments, _ in
        let factor = try arguments.integer(0, range: 1...10)
        let mode = try arguments.optionalChoice(1, among: ["up", "down"]) ?? "up"
        let number = try input.numberInput("probe")
        return .number(mode == "up" ? number * Double(factor) : -number)
    }

    static let accepting = BuiltinFilter("accepting", arity: FilterArity(0, 0), nullInput: .accept) { input, _, _ in
        .string(input.typeName)
    }

    @Test("adding ergänzt Filter ohne Stellenangabe, names ist sortiert")
    func adding() {
        let table = FilterTable(entries: [:])
            .adding("zeta") { input, _, _ in .value(input) }
            .adding("alpha") { _, _, _ in .value(.bool(true)) }
        #expect(table.names == ["alpha", "zeta"])
        #expect(table.arity(named: "alpha") == nil)
        #expect(table.function(named: "missing") == nil)
        let result = table.function(named: "zeta").map { $0(.number(4), [], FilterHarness.context) }
        #expect(result == .value(.number(4)))
    }

    @Test("Einträge aus BuiltinFilter tragen ihre Stellenzahl")
    func builtinEntries() {
        let table = FilterTable(entries: ["probe": FilterTable.Entry(function: { Self.probe.run($0, $1, $2) }, arity: Self.probe.arity)])
        #expect(table.arity(named: "probe") == FilterArity(1, 2))
        #expect(FilterArity(1, 2).accepts(2))
        #expect(FilterArity(1, 2).accepts(3) == false)
    }

    static let mechanicsCases: [(Value, [Value], FilterResult)] = [
        (.number(2), [.number(3)], .value(.number(6))),
        (.number(2), [.number(3), .string("down")], .value(.number(-2))),
        (.number(2), [.number(3), .null], .value(.number(6))),
        (.null, [.number(3)], .value(.null)),
        (.null, [], .failure("'probe' takes 1 to 2 arguments, got 0")),
        (.number(2), [], .failure("'probe' takes 1 to 2 arguments, got 0")),
        (.number(2), [.number(1.5)], .failure("'probe' expects a whole number from 1 to 10 as argument 1")),
        (.number(2), [.number(11)], .failure("'probe' expects a whole number from 1 to 10 as argument 1")),
        (.number(2), [.number(1e300)], .failure("'probe' expects a whole number from 1 to 10 as argument 1")),
        (.number(2), [.string("x")], .failure("'probe' expects a number as argument 1, got string")),
        (.number(2), [.number(1), .string("left")], .failure("'probe' expects 'up' or 'down' as argument 2, got 'left'")),
        (.string("a"), [.number(1)], .failure("'probe' expects a number, got string")),
    ]

    @Test("Stellenzahl, Null-Fortpflanzung, null als fehlendes optionales Argument, Fehlertexte", arguments: FilterTableTests.mechanicsCases)
    func mechanics(input: Value, arguments: [Value], expected: FilterResult) {
        #expect(Self.probe.run(input, arguments, FilterHarness.context) == expected)
    }

    @Test("nullInput .accept reicht null an den Rumpf weiter, Stellenzahl 1 heisst 'argument'")
    func acceptsNull() {
        #expect(Self.accepting.run(.null, [], FilterHarness.context) == .value(.string("null")))
        #expect(Self.accepting.run(.null, [.number(1)], FilterHarness.context) == .failure("'accepting' takes 0 arguments, got 1"))
        let single = BuiltinFilter("single", arity: FilterArity(1, 1)) { input, _, _ in input }
        #expect(single.run(.number(1), [], FilterHarness.context) == .failure("'single' takes 1 argument, got 0"))
    }

    @Test("Wahl aus drei Möglichkeiten nennt alle")
    func threeChoices() {
        let chooser = BuiltinFilter("chooser", arity: FilterArity(1, 1)) { _, arguments, _ in
            .string(try arguments.choice(0, among: ["a", "b", "c"]))
        }
        #expect(chooser.run(.null, [.string("d")], FilterHarness.context) == .value(.null))
        #expect(chooser.run(.number(1), [.string("d")], FilterHarness.context) == .failure("'chooser' expects 'a', 'b' or 'c' as argument 1, got 'd'"))
    }

    @Test("Eingangsprüfung für Listen, Records, Daten, Text und Folgen")
    func inputs() throws {
        #expect(try Value.list([.number(1)]).listInput("f") == [.number(1)])
        #expect(try Value.record(Record([("a", .null)])).recordInput("f").keys == ["a"])
        #expect(try Value.date(FilterHarness.now).dateInput("f") == FilterHarness.now)
        #expect(try Value.number(7).textInput("f") == "7")
        #expect(try Value.bool(false).textInput("f") == "false")
        #expect(throws: FilterFailure("'f' expects a string, got list")) { try Value.list([]).textInput("f") }
        #expect(throws: FilterFailure("'f' expects a list, got string")) { try Value.string("a").listInput("f") }
        #expect(throws: FilterFailure("'f' expects a record, got number")) { try Value.number(1).recordInput("f") }
        #expect(throws: FilterFailure("'f' expects a date, got number")) { try Value.number(1).dateInput("f") }
        #expect(throws: FilterFailure("'f' expects a list or a string, got number")) { try Value.number(1).sequenceInput("f") }
        guard case .text(let characters) = try Value.string("hé").sequenceInput("f") else {
            Issue.record("expected text")
            return
        }
        #expect(characters == ["h", "é"])
    }

    @Test("Ganzzahlen für Indizes: nur ganze, endliche Zahlen bis 10⁹, negative zählen von hinten")
    func indexing() {
        #expect(ValueIndexing.wholeNumber(3) == 3)
        #expect(ValueIndexing.wholeNumber(-2) == -2)
        #expect(ValueIndexing.wholeNumber(0.5) == nil)
        #expect(ValueIndexing.wholeNumber(.nan) == nil)
        #expect(ValueIndexing.wholeNumber(1e12) == nil)
        #expect(ValueIndexing.element([1, 2, 3], -1) == 3)
        #expect(ValueIndexing.element([1, 2, 3], 3) == nil)
        #expect(ValueIndexing.element([1, 2, 3], -4) == nil)
    }
}
