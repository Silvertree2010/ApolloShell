import Foundation

enum NumberFilters {
    static let digitRange = 0...15

    static let all: [BuiltinFilter] = [
        BuiltinFilter("round", arity: FilterArity(0, 1)) { input, arguments, _ in
            let number = try input.numberInput("round")
            let digits = try arguments.optionalInteger(0, default: 0, range: digitRange)
            return .number(NumberText.rounded(number, digits: digits))
        },
        BuiltinFilter("floor", arity: FilterArity(0, 0)) { input, _, _ in
            .number(try input.numberInput("floor").rounded(.down))
        },
        BuiltinFilter("ceil", arity: FilterArity(0, 0)) { input, _, _ in
            .number(try input.numberInput("ceil").rounded(.up))
        },
        BuiltinFilter("abs", arity: FilterArity(0, 0)) { input, _, _ in
            .number(Swift.abs(try input.numberInput("abs")))
        },
        BuiltinFilter("fixed", arity: FilterArity(1, 1)) { input, arguments, _ in
            let number = try input.numberInput("fixed")
            let digits = try arguments.integer(0, range: digitRange)
            return .string(NumberText.fixed(number, digits: digits))
        },
        BuiltinFilter("clamp", arity: FilterArity(2, 2)) { input, arguments, _ in
            let number = try input.numberInput("clamp")
            let low = try arguments.number(0)
            let high = try arguments.number(1)
            guard low <= high else {
                throw FilterFailure("'clamp' needs the lower bound first, got \(NumberText.plain(low)) and \(NumberText.plain(high))")
            }
            return .number(Swift.min(Swift.max(number, low), high))
        },
        BuiltinFilter("min", arity: FilterArity(1, 1)) { input, arguments, _ in
            .number(Swift.min(try input.numberInput("min"), try arguments.number(0)))
        },
        BuiltinFilter("max", arity: FilterArity(1, 1)) { input, arguments, _ in
            .number(Swift.max(try input.numberInput("max"), try arguments.number(0)))
        },
        BuiltinFilter("scale", arity: FilterArity(4, 4)) { input, arguments, _ in
            let number = try input.numberInput("scale")
            let fromLow = try arguments.number(0)
            let fromHigh = try arguments.number(1)
            let toLow = try arguments.number(2)
            let toHigh = try arguments.number(3)
            guard fromLow != fromHigh else { throw FilterFailure("'scale' needs two different input bounds") }
            let result = toLow + (number - fromLow) / (fromHigh - fromLow) * (toHigh - toLow)
            return result.isFinite ? .number(result) : .null
        },
        BuiltinFilter("percent", arity: FilterArity(0, 1)) { input, arguments, _ in
            let number = try input.numberInput("percent")
            let digits = try arguments.optionalInteger(0, default: 0, range: digitRange)
            let scaled = number * 100
            return scaled.isFinite ? .string(NumberText.fixed(scaled, digits: digits) + "%") : .null
        },
        BuiltinFilter("grouped", arity: FilterArity(0, 1)) { input, arguments, context in
            let number = try input.numberInput("grouped")
            let digits = try arguments.optionalInteger(0, default: 0, range: digitRange)
            return .string(NumberText.grouped(number, digits: digits, locale: context.locale))
        },
    ]
}
