import Testing
import Foundation
import ApolloBase
@testable import ApolloConfig

@Suite("Beispiele aus config-language.md mit den Standarddiensten")
struct SpecExampleTests {
    static let context = FilterContext(
        now: FilterHarness.now,
        locale: Locale(identifier: "en_US"),
        timeZone: TimeZone(identifier: "Europe/Zurich")!,
        services: DefaultFilterServices(calendar: DefaultFilterServicesTests.calendar)
    )

    static let scope = TestScope(
        locals: [
            "i": .number(0),
            "app": .record(Record([("name", .string("Safari"))])),
        ],
        globals: [
            "perf": .record(Record([
                ("cpu", .number(0.4242)),
                ("live", .record(Record([("memory-used", .number(2_147_483_648))]))),
            ])),
            "battery": .record(Record([("percent", .number(0.42))])),
            "media": .record(Record()),
            "system": .record(Record([("full-name", .string("andrin")), ("uptime", .number(183_600))])),
            "clock": .record(Record([("now", .date(FilterHarness.now))])),
            "var": .record(Record([
                ("index", .number(12)),
                ("calendar-offset", .number(0)),
                ("launcher-query", .string("fi")),
            ])),
            "apps": .record(Record([("all", .list(DefaultFilterServicesTests.apps))])),
        ]
    )

    static let examples: [(String, Value)] = [
        ("{perf.cpu * 100 | round}", .number(42)),
        ("{battery.percent | percent} left", .string("42% left")),
        ("{media.artist ?? 'Unknown'}", .string("Unknown")),
        ("{system.full-name | first | upper}", .string("A")),
        ("{clock.now | date 'HH:mm'}", .string("10:00")),
        ("{var.index | clamp 0 9}", .number(9)),
        ("{perf.live.memory-used / 1073741824 | fixed 1}", .string("2.0")),
        ("{'alt+space' | chord}", .string("⌥Space")),
        ("{system.uptime | duration 'short'}", .string("2d 3h")),
        ("{'example.com' | url}", .string("https://example.com")),
        ("{apps.all | app-search var.launcher-query | map 'name'}", .list([.string("Firefox"), .string("Affinity"), .string("Safari")])),
        ("{clock.now | month-grid var.calendar-offset | count}", .number(5)),
        ("{i + 1}. {app.name}", .string("1. Safari")),
        ("{{literal}} {media.title | upper}", .string("{literal} ")),
    ]

    @Test("jedes Beispiel ergibt den erwarteten Wert ohne Warnung", arguments: SpecExampleTests.examples)
    func example(text: String, expected: Value) throws {
        let sink = WarningSink()
        let evaluator = EvaluationHarness.evaluator(sink: sink, context: Self.context)
        let template = try ExpressionParser.parseTemplate(text, span: .synthetic("test")).get()
        #expect(evaluator.render(template, in: Self.scope) == expected)
        #expect(sink.diagnostics.isEmpty)
    }

    @Test("ein falscher Typ für einen Filter ergibt null und genau eine Warnung am Filter")
    func runtimeTypeError() throws {
        let sink = WarningSink()
        let evaluator = EvaluationHarness.evaluator(sink: sink, context: Self.context)
        let template = try ExpressionParser.parseTemplate("{system.full-name | round}", span: .synthetic("test")).get()
        #expect(evaluator.render(template, in: Self.scope) == .null)
        #expect(evaluator.render(template, in: Self.scope) == .null)
        #expect(sink.diagnostics.map(\.message) == ["'round' expects a number, got string"])
    }
}
