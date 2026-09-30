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
        BuiltinFilter("drop-frame", arity: FilterArity(4, 7)) { input, arguments, _ in
            let items = input == .null ? [] : try input.listInput("drop-frame")
            let w = try arguments.number(0)
            let h = try arguments.number(1)
            let x = try arguments.number(2)
            let y = try arguments.number(3)
            let page = try optionalNumber(arguments, 4) ?? 839
            let pageHeight = try optionalNumber(arguments, 5) ?? 392
            let gap = try optionalNumber(arguments, 6) ?? 12
            guard w > 0, h > 0, w.isFinite, h.isFinite, x.isFinite, y.isFinite else { throw FilterFailure("'drop-frame' needs a positive width and height and a finite position") }
            let geometry = CanvasGeometry(width: page, height: pageHeight, gap: gap)
            let others = items.compactMap(CanvasFrame.init)
            let frame = geometry.dropFrame(width: w, height: h, x: x, y: y, others: others)
            return geometry.isValid(frame, sizes: [], others: others) ? frame.value : .null
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
