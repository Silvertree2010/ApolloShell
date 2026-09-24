import Testing
import Foundation
@testable import ApolloConfig

@Suite("Listenfilter zum Suchen und sonstige Filter")
struct ListSearchFilterTests {
    static func module(_ id: String, _ kind: String) -> Value {
        .record(Record([("id", .string(id)), ("kind", .string(kind))]))
    }

    static let modules = Value.list([module("a", "clock"), module("b", "dock"), module("c", "clock")])

    static func app(_ name: String) -> Value {
        .record(Record([("name", .string(name)), ("title", .string(name.uppercased()))]))
    }

    static let apps = Value.list([app("Safari"), app("Affinity"), app("Firefox"), app("Notes")])

    static let cases: [FilterCase] = [
        .ok("where", modules, [.string("kind"), .string("clock")], .list([module("a", "clock"), module("c", "clock")])),
        .ok("where", .list([.number(1), module("a", "clock")]), [.string("kind"), .null], .list([.number(1)])),
        .ok("where-not", modules, [.string("kind"), .string("clock")], .list([module("b", "dock")])),
        .fails("where", .string("x"), [.string("kind"), .string("clock")]),
        .fails("where", modules, [.number(1), .string("clock")]),
        .fails("where-not", modules, [.string("kind")]),
        .ok("map", modules, [.string("id")], .list([.string("a"), .string("b"), .string("c")])),
        .ok("map", .list([.number(1)]), [.string("id")], .list([.null])),
        .fails("map", modules, []),
        .fails("map", .record(Record()), [.string("id")]),
        .ok("contains", .list([.number(1), .number(2)]), [.number(2)], .bool(true)),
        .ok("contains", .list([.number(1), .number(2)]), [.string("2")], .bool(false)),
        .ok("contains", modules, [module("b", "dock")], .bool(true)),
        .ok("contains", .string("hello"), [.string("ell")], .bool(true)),
        .ok("contains", .string("hello"), [.string("")], .bool(true)),
        .ok("contains", .string("a1"), [.number(1)], .bool(true)),
        .fails("contains", .record(Record()), [.string("a")]),
        .fails("contains", .string("hello"), [.list([])]),
        .ok("index-of", .list([.string("a"), .string("b")]), [.string("b")], .number(1)),
        .ok("index-of", .list([.string("a"), .string("b")]), [.string("z")], .null),
        .ok("index-of", .string("héllo"), [.string("l")], .number(2)),
        .ok("index-of", .string("hello"), [.string("z")], .null),
        .fails("index-of", .number(1), [.number(1)]),
        .ok("index-where", modules, [.string("id"), .string("b")], .number(1)),
        .ok("index-where", modules, [.string("id"), .list([.string("x"), .string("c")])], .number(2)),
        .ok("index-where", modules, [.string("kind"), .string("clock"), .string("last")], .number(2)),
        .ok("index-where", modules, [.string("kind"), .string("clock")], .number(0)),
        .ok("index-where", modules, [.string("id"), .string("z")], .null),
        .fails("index-where", modules, [.string("id"), .string("a"), .string("first")]),
        .fails("index-where", modules, [.string("id")]),
        .ok("fuzzy", apps, [.string("fi")], .list([app("Firefox"), app("Affinity"), app("Safari")])),
        .ok("fuzzy", apps, [.string("FI"), .string("title")], .list([app("Firefox"), app("Affinity"), app("Safari")])),
        .ok("fuzzy", .list([.string("Firefox"), .string("Finder")]), [.string("ff")], .list([.string("Firefox")])),
        .ok("fuzzy", apps, [.string("")], apps),
        .ok("fuzzy", apps, [.null], apps),
        .fails("fuzzy", .number(5), [.string("a")]),
        .fails("fuzzy", apps, [.number(5)]),
        .ok("default", .null, [.number(5)], .number(5)),
        .ok("default", .number(0), [.number(5)], .number(0)),
        .ok("default", .string(""), [.string("x")], .string("")),
        .fails("default", .null, []),
        .ok("bool", .number(0), [], .bool(false)),
        .ok("bool", .string("x"), [], .bool(true)),
        .ok("bool", .null, [], .bool(false)),
        .ok("bool", .list([]), [], .bool(false)),
        .fails("bool", .null, [.number(1)]),
        .ok("keys", .record(Record([("b", .number(1)), ("a", .number(2))])), [], .list([.string("b"), .string("a")])),
        .ok("values", .record(Record([("b", .number(1)), ("a", .number(2))])), [], .list([.number(1), .number(2)])),
        .ok("keys", .null, [], .null),
        .fails("keys", .list([.number(1)]), []),
        .fails("values", .string("a"), []),
    ]

    @Test("jeder Such- und sonstige Filter mit gültigen und ungültigen Eingaben", arguments: ListSearchFilterTests.cases)
    func filters(testCase: FilterCase) {
        FilterHarness.check(testCase)
    }

    @Test("where auf 50 000 Einträgen bleibt schnell")
    func whereLargeList() {
        let items = Value.list((0..<50_000).map { Self.module("id-\($0)", $0 % 2 == 0 ? "clock" : "dock") })
        let function = FilterTable.builtin.function(named: "where")!
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = function(items, [.string("kind"), .string("clock")], FilterHarness.context)
        }
        #expect(elapsed < .seconds(3))
    }
}
