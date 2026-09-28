import Foundation
import ApolloShellCore

enum UnitFilters {
    static let all: [BuiltinFilter] = [
        BuiltinFilter("bytes", arity: FilterArity(0, 1)) { input, arguments, context in
            let count = try byteCount(input, filter: "bytes")
            let binary = try arguments.optionalChoice(0, among: ["binary", "decimal"]) == "binary"
            return .string(ByteFormat.bytes(count, binary: binary, locale: context.locale))
        },
        BuiltinFilter("bytes-per-second", arity: FilterArity(0, 1)) { input, arguments, context in
            let count = try byteCount(input, filter: "bytes-per-second")
            let binary = try arguments.optionalChoice(0, among: ["binary", "decimal"]) == "binary"
            return .string(ByteFormat.bytes(count, binary: binary, locale: context.locale) + "/s")
        },
        BuiltinFilter("temperature", arity: FilterArity(0, 0)) { input, _, context in
            let celsius = try input.numberInput("temperature")
            guard Swift.abs(celsius) < 1_000_000 else { throw FilterFailure("'temperature' got a number that is too large") }
            return .string(context.services.temperatureText(celsius))
        },
        BuiltinFilter("duration", arity: FilterArity(0, 1)) { input, arguments, context in
            let seconds = try input.numberInput("duration")
            guard Swift.abs(seconds) < 1e12 else { throw FilterFailure("'duration' got a number that is too large") }
            let style = try arguments.optionalChoice(0, among: ["short", "clock"]) ?? "clock"
            return .string(style == "short" ? context.services.uptimeText(seconds) : DurationText.clock(seconds))
        },
        BuiltinFilter("date", arity: FilterArity(1, 2)) { input, arguments, context in
            let date = try input.dateInput("date")
            let pattern = try arguments.string(0)
            var timeZone = context.timeZone
            if let identifier = try arguments.optionalString(1) {
                guard let zone = TimeZone(identifier: identifier) else {
                    throw FilterFailure("'date' does not know the time zone '\(identifier)'")
                }
                timeZone = zone
            }
            return .string(DateText.format(date, pattern: pattern, locale: context.locale, timeZone: timeZone))
        },
        BuiltinFilter("relative", arity: FilterArity(0, 0)) { input, _, context in
            .string(DateText.relative(try input.dateInput("relative"), now: context.now))
        },
    ]

    static func byteCount(_ input: Value, filter: String) throws -> Double {
        let count = try input.numberInput(filter)
        guard Swift.abs(count) < 1e18 else { throw FilterFailure("'\(filter)' got a number that is too large") }
        return count
    }
}
