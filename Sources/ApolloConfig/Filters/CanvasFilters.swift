import Foundation

enum CanvasFilters {
    static let all: [BuiltinFilter] = [
        BuiltinFilter("first-free-frame", arity: FilterArity(2, 5)) { input, arguments, _ in
            let items = input == .null ? [] : try input.listInput("first-free-frame")
            let w = try arguments.number(0)
            let h = try arguments.number(1)
            let page = try optionalNumber(arguments, 2) ?? 839
            let pageHeight = try optionalNumber(arguments, 3) ?? 392
            let gap = try optionalNumber(arguments, 4) ?? 12
            guard w > 0, h > 0, w.isFinite, h.isFinite else { throw FilterFailure("'first-free-frame' needs a positive width and height") }
            let geometry = CanvasGeometry(width: page, height: pageHeight, gap: gap)
            return geometry.firstFreeFrame(width: w, height: h, others: items.compactMap(CanvasFrame.init))?.value ?? .null
        },
        BuiltinFilter("sun-moon", arity: FilterArity(2, 2)) { input, arguments, _ in
            let date = try input.dateInput("sun-moon")
            let latitude = try arguments.number(0)
            let longitude = try arguments.number(1)
            guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
                throw FilterFailure("'sun-moon' needs a latitude from -90 to 90 and a longitude from -180 to 180")
            }
            return SunMoon.record(date, latitude: latitude, longitude: longitude)
        },
    ]

    static func optionalNumber(_ arguments: FilterArguments, _ index: Int) throws -> Double? {
        arguments.value(index) == .null ? nil : try arguments.number(index)
    }
}
