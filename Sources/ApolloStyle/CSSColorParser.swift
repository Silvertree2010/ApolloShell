import ApolloShellCore

enum CSSColorParser {
    static let systemColorNames: [String] = [
        "-apple-system-label",
        "-apple-system-secondary-label",
        "-apple-system-tertiary-label",
        "-apple-system-quaternary-label",
        "-apple-system-separator",
        "-apple-system-control-accent",
        "-apple-system-window-background",
        "-apple-system-control-background",
        "-apple-system-text-background",
        "-apple-system-selected-content-background",
        "-apple-system-red",
        "-apple-system-orange",
        "-apple-system-yellow",
        "-apple-system-green",
        "-apple-system-mint",
        "-apple-system-teal",
        "-apple-system-cyan",
        "-apple-system-blue",
        "-apple-system-indigo",
        "-apple-system-purple",
        "-apple-system-pink",
        "-apple-system-brown",
        "-apple-system-gray",
        "-apollo-accent-text",
        "-apollo-contrast-accent",
    ]

    private static let systemColorSet = Set(systemColorNames)

    static func color(_ components: [CSSComponent]) throws -> CSSColor {
        try color(CSSRead.single(components))
    }

    static func color(_ component: CSSComponent) throws -> CSSColor {
        switch component {
        case let .token(token):
            switch token.kind {
            case let .ident(name):
                let lower = name.lowercased()
                if lower == "currentcolor" { return .currentColor }
                if systemColorSet.contains(lower) { return .system(name: lower, alpha: 1) }
                if let color = ThemeValueReader.color(lower) { return rgba(color) }
                throw CSSValueError("unknown color '\(name)'")
            case let .hash(value):
                if let color = ThemeValueReader.color("#" + value) { return rgba(color) }
                throw CSSValueError("invalid hex color '#\(value)'")
            default:
                break
            }
        case let .function(name, arguments, _):
            let lower = name.lowercased()
            let words = CSSList.words(arguments)
            if lower == "rgb", words.first?.lowercasedIdent == "from" { return try relative(words) }
            if lower == "contrast" { return try contrast(arguments) }
            if ["rgb", "rgba", "hsl", "hsla"].contains(lower) {
                guard words.first?.lowercasedIdent != "from" else {
                    throw CSSValueError("relative colors are only supported as rgb(from <color> r g b / <alpha>)")
                }
                if let color = ThemeValueReader.color(component.text) { return rgba(color) }
                throw CSSValueError("invalid color '\(component.text)'")
            }
        case .block:
            break
        }
        throw CSSValueError("expected a color, found '\(component.text)'")
    }

    static func rgba(_ color: ThemeColor) -> CSSColor {
        .rgba(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    private static func contrast(_ arguments: [CSSComponent]) throws -> CSSColor {
        switch try color(arguments) {
        case let .rgba(red, green, blue, alpha):
            let top = max(red, green, blue), low = min(red, green, blue), span = top - low
            guard top > 0, span / top > 0.15 else {
                let grey = top > 0.5 ? 0.35 : 0.75
                return .rgba(red: grey, green: grey, blue: grey, alpha: alpha)
            }
            var hue: Double
            if top == red { hue = ((green - blue) / span).truncatingRemainder(dividingBy: 6) }
            else if top == green { hue = (blue - red) / span + 2 }
            else { hue = (red - green) / span + 4 }
            hue = (hue / 6 + 0.5).truncatingRemainder(dividingBy: 1)
            if hue < 0 { hue += 1 }
            let value = max(top, 0.85), chroma = value * span / top
            let sector = hue * 6, x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1)), m = value - chroma
            let parts: (Double, Double, Double) = switch Int(sector) {
            case 0: (chroma, x, 0)
            case 1: (x, chroma, 0)
            case 2: (0, chroma, x)
            case 3: (0, x, chroma)
            case 4: (x, 0, chroma)
            default: (chroma, 0, x)
            }
            return .rgba(red: parts.0 + m, green: parts.1 + m, blue: parts.2 + m, alpha: alpha)
        case let .system(name, alpha):
            return name == "-apple-system-control-accent" ? .system(name: "-apollo-contrast-accent", alpha: alpha) : .system(name: name, alpha: alpha)
        case .currentColor:
            throw CSSValueError("contrast(currentcolor) is not supported")
        }
    }

    private static func relative(_ words: [CSSComponent]) throws -> CSSColor {
        guard words.count == 7,
              words[2].lowercasedIdent == "r", words[3].lowercasedIdent == "g", words[4].lowercasedIdent == "b",
              words[5].delimCharacter == "/"
        else { throw CSSValueError("relative colors are only supported as rgb(from <color> r g b / <alpha>)") }
        let alpha = try CSSRead.ratio(words[6])
        switch try color(words[1]) {
        case let .rgba(red, green, blue, _):
            return .rgba(red: red, green: green, blue: blue, alpha: alpha)
        case let .system(name, _):
            return .system(name: name, alpha: alpha)
        case .currentColor:
            throw CSSValueError("rgb(from currentcolor …) is not supported")
        }
    }
}
