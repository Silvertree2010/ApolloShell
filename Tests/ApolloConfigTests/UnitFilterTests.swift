import Testing
import Foundation
@testable import ApolloConfig

@Suite("Einheiten- und Zeitfilter")
struct UnitFilterTests {
    static let now = FilterHarness.now

    static let cases: [FilterCase] = [
        .ok("bytes", .number(1536), [], .string("1.5 KB")),
        .ok("bytes", .number(1536), [.string("binary")], .string("1.5 KB")),
        .ok("bytes", .number(25_769_803_776), [.string("binary")], .string("24 GB")),
        .ok("bytes", .number(999), [], .string("999 B")),
        .ok("bytes", .number(340_000), [.string("decimal")], .string("340 KB")),
        .ok("bytes", .number(-5), [], .string("0 B")),
        .ok("bytes", .null, [], .null),
        .fails("bytes", .string("a"), []),
        .fails("bytes", .number(1), [.string("octal")]),
        .fails("bytes", .number(1e30), []),
        .ok("bytes-per-second", .number(1_200_000), [], .string("1.2 MB/s")),
        .ok("bytes-per-second", .number(2048), [.string("binary")], .string("2.0 KB/s")),
        .fails("bytes-per-second", .bool(true), []),
        .ok("temperature", .number(21.4), [], .string("21°C")),
        .fails("temperature", .string("x"), []),
        .fails("temperature", .number(1e9), []),
        .fails("temperature", .number(1), [.string("f")]),
        .ok("duration", .number(3900), [], .string("1:05:00")),
        .ok("duration", .number(300), [.string("clock")], .string("5:00")),
        .ok("duration", .number(59.9), [], .string("0:59")),
        .ok("duration", .number(-90), [], .string("-1:30")),
        .ok("duration", .number(183_600), [.string("short")], .string("uptime 183600")),
        .fails("duration", .string("x"), []),
        .fails("duration", .number(1), [.string("long")]),
        .fails("duration", .number(1e15), []),
        .ok("date", .date(now), [.string("HH:mm")], .string("10:00")),
        .ok("date", .date(now), [.string("yyyy-MM-dd")], .string("2026-09-24")),
        .ok("date", .date(now), [.string("EEEE")], .string("Thursday")),
        .ok("date", .null, [.string("HH:mm")], .null),
        .fails("date", .number(5), [.string("HH:mm")]),
        .fails("date", .date(now), []),
        .fails("date", .date(now), [.number(5)]),
        .ok("relative", .date(now.addingTimeInterval(300)), [], .string("in 5 min")),
        .ok("relative", .date(now.addingTimeInterval(-7200)), [], .string("2 h ago")),
        .ok("relative", .date(now.addingTimeInterval(-5400)), [], .string("1 h ago")),
        .ok("relative", .date(now.addingTimeInterval(-30)), [], .string("now")),
        .ok("relative", .date(now.addingTimeInterval(259_200)), [], .string("in 3 d")),
        .fails("relative", .string("yesterday"), []),
        .fails("relative", .date(now), [.string("short")]),
    ]

    @Test("jeder Einheiten- und Zeitfilter mit gültigen und ungültigen Eingaben", arguments: UnitFilterTests.cases)
    func filters(testCase: FilterCase) {
        FilterHarness.check(testCase)
    }

    @Test("bytes folgt der Locale wie ByteFormat in 0.1.4.2")
    func locale() {
        var context = FilterHarness.context
        context.locale = Locale(identifier: "de_DE")
        FilterHarness.check(.ok("bytes", .number(1536), [], .string("1,5 KB")), context: context)
        FilterHarness.check(.ok("date", .date(Self.now), [.string("EEEE")], .string("Donnerstag")), context: context)
    }
}
