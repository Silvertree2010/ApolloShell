import Testing
import Foundation
@testable import ApolloConfig

@Suite("Fachfilter")
struct DomainFilterTests {
    static let now = FilterHarness.now

    static func app(_ name: String) -> Value {
        .record(Record([("name", .string(name))]))
    }

    static let apps = Value.list([app("Safari"), app("Firefox")])

    static let cases: [FilterCase] = [
        .ok("app-search", apps, [.string("fire")], .list([app("Firefox")])),
        .ok("app-search", apps, [.null], apps),
        .ok("app-search", apps, [.string("")], apps),
        .ok("app-search", .null, [.string("a")], .null),
        .fails("app-search", .string("x"), [.string("a")]),
        .fails("app-search", apps, [.number(1)]),
        .fails("app-search", apps, []),
        .ok("month-grid", .date(now), [], .string("grid 0 system")),
        .ok("month-grid", .date(now), [.number(1), .string("monday")], .string("grid 1 monday")),
        .ok("month-grid", .date(now), [.null, .string("sunday")], .string("grid 0 sunday")),
        .ok("month-grid", .date(now), [.number(-2), .null], .string("grid -2 system")),
        .fails("month-grid", .date(now), [.string("x")]),
        .fails("month-grid", .date(now), [.number(0), .string("friday")]),
        .fails("month-grid", .date(now), [.number(0.5)]),
        .fails("month-grid", .string("x"), []),
        .ok("url", .string("example.com"), [], .string("https://example.com")),
        .ok("url", .string("nope"), [], .null),
        .ok("url", .null, [], .null),
        .fails("url", .number(5), []),
        .fails("url", .string("a.b"), [.string("x")]),
        .ok("symbol-exists", .string("star.fill"), [], .bool(true)),
        .ok("symbol-exists", .string("nope"), [], .bool(false)),
        .fails("symbol-exists", .number(5), []),
        .ok("chord", .string("alt+space"), [], .string("display alt+space")),
        .ok("chord", .string("opt+space"), [], .string("display alt+space")),
        .ok("chord", .string(""), [], .string("")),
        .fails("chord", .string("alt+nokey"), []),
        .fails("chord", .number(5), []),
        .ok("hotkey-warning", .string("cmd+space"), [], .string("taken")),
        .ok("hotkey-warning", .string("ctrl+alt+d"), [], .null),
        .ok("hotkey-warning", .string(""), [], .null),
        .fails("hotkey-warning", .string("foo+x"), []),
        .fails("hotkey-warning", .list([]), []),
    ]

    @Test("jeder Fachfilter mit gültigen und ungültigen Eingaben", arguments: DomainFilterTests.cases)
    func filters(testCase: FilterCase) {
        FilterHarness.check(testCase)
    }
}
