import Testing
import Foundation
@testable import ApolloConfig

@Suite("Listenfilter für Form und Reihenfolge")
struct ListShapeFilterTests {
    static let numbers = Value.list([.number(1), .number(2), .number(3)])

    static func item(_ name: String, _ rank: Double) -> Value {
        .record(Record([("name", .string(name)), ("n", .number(rank))]))
    }

    static let cases: [FilterCase] = [
        .ok("count", numbers, [], .number(3)),
        .ok("count", .string("héllo"), [], .number(5)),
        .ok("count", .string("👍🏽"), [], .number(1)),
        .ok("count", .record(Record([("a", .null), ("b", .null)])), [], .number(2)),
        .ok("count", .null, [], .null),
        .fails("count", .number(5), []),
        .ok("first", numbers, [], .number(1)),
        .ok("first", .list([]), [], .null),
        .ok("first", .string("andrin"), [], .string("a")),
        .ok("first", .string("👍🏽x"), [], .string("👍🏽")),
        .ok("last", .string("ab"), [], .string("b")),
        .ok("last", .list([]), [], .null),
        .ok("last", numbers, [], .number(3)),
        .fails("first", .number(5), []),
        .fails("last", .bool(true), []),
        .ok("at", numbers, [.number(1)], .number(2)),
        .ok("at", numbers, [.number(-1)], .number(3)),
        .ok("at", numbers, [.number(5)], .null),
        .ok("at", .string("abc"), [.number(0)], .string("a")),
        .fails("at", numbers, [.string("x")]),
        .fails("at", numbers, [.number(0.5)]),
        .fails("at", numbers, [.number(1e300)]),
        .ok("take", numbers, [.number(2)], .list([.number(1), .number(2)])),
        .ok("take", .string("abc"), [.number(5)], .string("abc")),
        .fails("take", numbers, [.number(-1)]),
        .ok("skip", numbers, [.number(1)], .list([.number(2), .number(3)])),
        .ok("skip", .string("abc"), [.number(9)], .string("")),
        .fails("skip", .number(1), [.number(1)]),
        .ok("slice", .list([.number(1), .number(2), .number(3), .number(4)]), [.number(1), .number(3)], .list([.number(2), .number(3)])),
        .ok("slice", .list([.number(1), .number(2), .number(3), .number(4)]), [.number(-2), .number(4)], .list([.number(3), .number(4)])),
        .ok("slice", .string("hello"), [.number(1), .number(-1)], .string("ell")),
        .ok("slice", .list([.number(1), .number(2)]), [.number(2), .number(1)], .list([])),
        .fails("slice", numbers, [.number(1)]),
        .ok("reverse", numbers, [], .list([.number(3), .number(2), .number(1)])),
        .ok("reverse", .string("abc"), [], .string("cba")),
        .fails("reverse", .number(1), []),
        .ok("sort", .list([.number(3), .number(1), .number(2)]), [], numbers),
        .ok("sort", .list([.string("b"), .string("a"), .string("C")]), [], .list([.string("a"), .string("b"), .string("C")])),
        .ok("sort", .list([.string("item 10"), .string("item 9")]), [], .list([.string("item 9"), .string("item 10")])),
        .ok("sort", .list([.number(3), .number(1), .number(2)]), [.string("desc")], .list([.number(3), .number(2), .number(1)])),
        .ok("sort", .list([item("b", 2), item("a", 1), item("c", 2)]), [.string("n")], .list([item("a", 1), item("b", 2), item("c", 2)])),
        .ok("sort", .list([item("b", 2), item("a", 1), item("c", 2)]), [.string("n"), .string("desc")], .list([item("b", 2), item("c", 2), item("a", 1)])),
        .ok("sort", .list([.string("x"), .null, .number(1)]), [], .list([.null, .number(1), .string("x")])),
        .fails("sort", numbers, [.string("n"), .string("up")]),
        .fails("sort", .string("abc"), []),
        .ok("unique", .list([.number(1), .number(2), .number(1), .number(3), .number(2)]), [], numbers),
        .fails("unique", .string("aab"), []),
        .ok("join", .list([.string("a"), .number(1), .null]), [.string(", ")], .string("a, 1, ")),
        .ok("join", .list([]), [.string(",")], .string("")),
        .fails("join", .string("abc"), [.string(",")]),
        .fails("join", numbers, []),
    ]

    @Test("jeder Listenfilter für Form und Reihenfolge mit gültigen und ungültigen Eingaben", arguments: ListShapeFilterTests.cases)
    func filters(testCase: FilterCase) {
        FilterHarness.check(testCase)
    }

    @Test("sort auf 50 000 Einträgen bleibt schnell")
    func sortLargeList() {
        let items = Value.list((0..<50_000).map { .number(Double(50_000 - $0)) })
        let function = FilterTable.builtin.function(named: "sort")!
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = function(items, [], FilterHarness.context)
        }
        #expect(elapsed < .seconds(3))
    }

    @Test("unique auf 50 000 Einträgen bleibt schnell")
    func uniqueLargeList() {
        let items = Value.list((0..<50_000).map { .number(Double($0 % 1_000)) })
        let function = FilterTable.builtin.function(named: "unique")!
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = function(items, [], FilterHarness.context)
        }
        #expect(elapsed < .seconds(3))
    }

    static func context(locale: Locale) -> FilterContext {
        FilterContext(now: FilterHarness.now, locale: locale, timeZone: FilterHarness.context.timeZone, services: FakeFilterServices())
    }

    static func sorted(_ input: Value, in context: FilterContext) -> Value {
        guard case .value(let value) = FilterTable.builtin.function(named: "sort")!(input, [], context) else {
            Issue.record("'sort' failed")
            return .null
        }
        return value
    }

    @Test("sort vergleicht Strings nach FilterContext.locale, nicht nach der Locale des Prozesses")
    func sortUsesContextLocale() {
        let words = Value.list([.string("z"), .string("ä")])
        let swedish = Self.context(locale: Locale(identifier: "sv_SE"))
        let german = Self.context(locale: Locale(identifier: "de_DE"))
        #expect(Self.sorted(words, in: swedish) == .list([.string("z"), .string("ä")]))
        #expect(Self.sorted(words, in: german) == .list([.string("ä"), .string("z")]))
    }

    @Test("sort ignoriert die Locale des Mac, auf dem die Tests laufen")
    func sortIgnoresProcessLocale() {
        let words = Value.list([.string("z"), .string("ä")])
        #expect(Locale.current.identifier != "sv_SE")
        let swedish = Self.context(locale: Locale(identifier: "sv_SE"))
        #expect(Self.sorted(words, in: swedish) == .list([.string("z"), .string("ä")]))
    }
}
