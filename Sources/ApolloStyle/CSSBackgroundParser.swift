import ApolloShellCore
import Foundation

extension CSSParseContext {
    func image(_ reference: String) throws -> String {
        guard let assetRoot else {
            throw CSSValueError("url(\"\(reference)\") needs a config or package folder", assetRejection: .needsThemeFolder)
        }
        switch ThemeAssetResolver.folder(assetRoot, limits: limits)(reference) {
        case let .success(url):
            return url.path
        case let .failure(reason):
            throw CSSValueError("image \"\(reference)\" rejected: \(reason.description)", assetRejection: reason)
        }
    }
}

enum CSSBackgroundParser {
    static let unsupportedGradients: Set<String> = [
        "radial-gradient", "conic-gradient", "repeating-linear-gradient", "repeating-radial-gradient", "repeating-conic-gradient",
    ]

    static func layers(_ components: [CSSComponent], context: CSSParseContext) throws -> [BackgroundLayer] {
        let parts = CSSList.commaSeparated(components)
        if parts.count == 1, parts[0].count == 1, parts[0][0].lowercasedIdent == "none" { return [] }
        return try parts.map { try layer($0, context: context) }
    }

    static func layer(_ words: [CSSComponent], context: CSSParseContext) throws -> BackgroundLayer {
        guard words.count == 1 else {
            throw CSSValueError(words.isEmpty ? "a background layer is missing" : "each background layer is one value, found '\(CSSList.text(words))'")
        }
        let item = words[0]
        if case let .url(reference)? = item.tokenKind { return .image(path: try context.image(reference)) }
        if let name = item.functionName {
            switch name {
            case "linear-gradient": return .gradient(try gradient(item))
            case "url": return .image(path: try context.image(try urlArgument(item)))
            case "glass": return try glass(item)
            case "material": return try material(item)
            default:
                if unsupportedGradients.contains(name) { throw CSSValueError("\(name)() is not supported; use linear-gradient()") }
            }
        }
        return .color(try CSSColorParser.color(item))
    }

    static func paint(_ components: [CSSComponent]) throws -> [BackgroundLayer] {
        let item = try CSSRead.single(components)
        if item.functionName == "linear-gradient" { return [.gradient(try gradient(item))] }
        if let name = item.functionName, unsupportedGradients.contains(name) {
            throw CSSValueError("\(name)() is not supported; use linear-gradient()")
        }
        return [.color(try CSSColorParser.color(item))]
    }

    static func gradient(_ component: CSSComponent) throws -> LinearGradient {
        guard case let .function(_, arguments, _) = component else { throw CSSValueError("expected linear-gradient()") }
        var parts = CSSList.commaSeparated(arguments)
        var angle = 180.0
        if let first = parts.first, let value = try direction(first) {
            angle = value
            parts.removeFirst()
        }
        guard (2...8).contains(parts.count) else { throw CSSValueError("linear-gradient() needs 2 to 8 colors") }
        var colors: [CSSColor] = []
        var positions: [Double?] = []
        for part in parts {
            guard part.count == 1 || part.count == 2 else {
                throw CSSValueError("a gradient stop is <color> [<percentage>], found '\(CSSList.text(part))'")
            }
            colors.append(try CSSColorParser.color(part[0]))
            if part.count == 2 {
                guard let value = try CSSNumbers.numeric(part[1]), value.dimension == .percent else {
                    throw CSSValueError("gradient stop positions are percentages, found '\(part[1].text)'")
                }
                positions.append(value.value / 100)
            } else {
                positions.append(nil)
            }
        }
        var stops: [GradientStop] = []
        var previous = 0.0
        for (index, color) in colors.enumerated() {
            let even = Double(index) / Double(colors.count - 1)
            let position = max(previous, min(max(positions[index] ?? even, 0), 1))
            stops.append(GradientStop(color: color, position: position))
            previous = position
        }
        return LinearGradient(angleDegrees: angle, stops: stops)
    }

    private static func direction(_ words: [CSSComponent]) throws -> Double? {
        if words.first?.lowercasedIdent == "to" {
            let sides = words.dropFirst().compactMap(\.lowercasedIdent)
            guard sides.count == words.count - 1, (1...2).contains(sides.count) else {
                throw CSSValueError("a gradient direction is 'to' and one or two sides")
            }
            switch sides.sorted().joined(separator: " ") {
            case "top": return 0
            case "right": return 90
            case "bottom": return 180
            case "left": return 270
            case "right top": return 45
            case "bottom right": return 135
            case "bottom left": return 225
            case "left top": return 315
            default: throw CSSValueError("unknown gradient direction '\(CSSList.text(words))'")
            }
        }
        guard words.count == 1, let value = try CSSNumbers.numeric(words[0]) else { return nil }
        guard value.dimension == .angle || (value.dimension == .number && value.value == 0) else {
            throw CSSValueError("a gradient angle is written like 90deg, found '\(words[0].text)'")
        }
        return value.value
    }

    private static func urlArgument(_ component: CSSComponent) throws -> String {
        guard case let .function(_, arguments, _) = component,
              case let .string(reference)? = try CSSRead.single(arguments).tokenKind
        else { throw CSSValueError("url() takes one file name") }
        return reference
    }

    private static func glass(_ component: CSSComponent) throws -> BackgroundLayer {
        guard case let .function(_, arguments, _) = component else { throw CSSValueError("expected glass()") }
        let parts = CSSList.commaSeparated(arguments)
        guard (1...2).contains(parts.count), parts[0].count == 1,
              let name = parts[0][0].lowercasedIdent, let variant = GlassVariant(rawValue: name)
        else { throw CSSValueError("glass() takes regular or clear and an optional tint color") }
        let tint: CSSColor? = try parts.count == 2 ? CSSColorParser.color(parts[1]) : nil
        return .glass(variant, tint: tint)
    }

    private static func material(_ component: CSSComponent) throws -> BackgroundLayer {
        guard case let .function(_, arguments, _) = component,
              let name = try CSSRead.single(arguments).lowercasedIdent,
              let thickness = MaterialThickness(rawValue: name)
        else { throw CSSValueError("material() takes ultra-thin, thin, regular, thick, ultra-thick or bar") }
        return .material(thickness)
    }
}
