import Foundation

/// Reads a single value out of a theme file - the CSS subset the format
/// commits to.
///
/// Whatever cannot be read safely here is `nil`; the caller then takes the
/// default and reports a notice with a line number. Nothing is guessed: a
/// half-understood value would be worse than the default.
public enum ThemeValueReader {
    public static func read(_ raw: String, kind: ThemeTokenKind) -> ThemeValue? {
        guard let text = prepared(raw) else { return nil }
        switch kind {
        case .color:
            return color(text).map(ThemeValue.color)
        case .gradient:
            return gradient(text).map(ThemeValue.gradient)
        case let .number(spec):
            guard let value = number(text, unit: spec.unit), value.isFinite else { return nil }
            return .number(value)
        case .text:
            return .text(plainText(text))
        case .file:
            return file(text).map { .file(ThemeAsset(reference: $0, url: nil)) }
        case let .option(values):
            let option = text.lowercased()
            guard values.contains(option) else { return nil }
            return .option(option)
        case .flag:
            return flag(text).map(ThemeValue.flag)
        }
    }

    /// Trimmed, without `!important`, without control characters. `nil` when
    /// nothing is left or something stands in it that this version explicitly
    /// does not understand.
    private static func prepared(_ raw: String) -> String? {
        var text = raw.trimmedText
        if let range = text.range(of: "!important", options: [.caseInsensitive, .backwards]),
           range.upperBound == text.endIndex {
            text = String(text[..<range.lowerBound]).trimmedText
        }
        guard !text.isEmpty else { return nil }
        // There is no `var(--x)`: without a lookup chain the format stays
        // manageable, and nobody builds on behavior we could not keep later.
        // nicht halten koennen.
        guard !text.lowercased().contains("var(") else { return nil }
        return text
    }

    // MARK: - Colors

    public static func color(_ raw: String) -> ThemeColor? {
        let text = raw.trimmedText
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("#") { return hex(String(text.dropFirst())) }
        guard let open = text.firstIndex(of: "("), text.hasSuffix(")") else {
            return named[text.lowercased()]
        }
        let function = String(text[text.startIndex..<open]).lowercased().trimmedText
        let inside = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
        switch function {
        case "rgb", "rgba": return rgb(inside)
        case "hsl", "hsla": return hsl(inside)
        default: return nil
        }
    }

    // MARK: - Gradients

    /// `none` or `linear-gradient(<angle>deg, <color> <position>%, ...)`.
    ///
    /// The angle may be missing, and then it runs from top to bottom (180
    /// degrees, as in CSS). Positions may be missing, and then the colors are
    /// spread evenly. Fewer than two colors is no gradient but an error -
    /// whoever wants to color an area takes the color token next to it.
    ///
    public static func gradient(_ raw: String) -> ThemeGradient? {
        let text = raw.trimmedText
        guard !text.isEmpty else { return nil }
        // ThemeGradient.none, not Optional.none: in a function that hands back
        // `ThemeGradient?`, `.none` would be the empty optional - so
        // "unreadable" instead of "no gradient".
        if text.lowercased() == "none" { return ThemeGradient.none }
        guard let open = text.firstIndex(of: "("), text.hasSuffix(")") else { return nil }
        let function = String(text[text.startIndex..<open]).lowercased().trimmedText
        // Straight gradients only. A theme that writes `radial-gradient` gets
        // a notice instead of an approximation.
        guard function == "linear-gradient" else { return nil }
        let inside = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
        var parts = splitTopLevel(inside)
        guard !parts.isEmpty else { return nil }

        var angle = 180.0
        if let first = parts.first, isAngle(first) {
            guard let value = self.angle(first) else { return nil }
            angle = value
            parts.removeFirst()
        }
        guard parts.count >= 2, parts.count <= ThemeGradient.maximumStops else { return nil }

        var colors: [ThemeColor] = []
        var positions: [Double?] = []
        for part in parts {
            guard let (color, position) = stop(part) else { return nil }
            colors.append(color)
            positions.append(position)
        }
        // Spread missing positions evenly, and never backwards: a position
        // before its predecessor would be allowed in CSS (a hard edge), but
        // here it is more likely a slip.
        var stops: [ThemeGradient.Stop] = []
        var previous = 0.0
        for (index, color) in colors.enumerated() {
            let even = colors.count == 1 ? 0 : Double(index) / Double(colors.count - 1)
            let wanted = positions[index] ?? even
            let position = max(previous, wanted)
            stops.append(ThemeGradient.Stop(color: color, position: position))
            previous = position
        }
        return ThemeGradient(angle: angle, stops: stops)
    }

    /// Splits at commas, but not inside brackets - `rgb(0, 0, 0)` stays one
    /// piece.
    private static func splitTopLevel(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for character in text {
            switch character {
            case "(": depth += 1; current.append(character)
            case ")": depth -= 1; current.append(character)
            case "," where depth == 0:
                parts.append(current.trimmedText)
                current = ""
            default: current.append(character)
            }
        }
        parts.append(current.trimmedText)
        return parts.filter { !$0.isEmpty }
    }

    private static func isAngle(_ part: String) -> Bool {
        let text = part.lowercased()
        return text.hasSuffix("deg") || text.hasPrefix("to ")
    }

    /// `45deg` or the words of CSS (`to bottom`, `to right` ...).
    private static func angle(_ part: String) -> Double? {
        let text = part.lowercased().trimmedText
        if text.hasPrefix("to ") {
            switch String(text.dropFirst(3)).trimmedText {
            case "top": return 0
            case "right": return 90
            case "bottom": return 180
            case "left": return 270
            case "top right", "right top": return 45
            case "bottom right", "right bottom": return 135
            case "bottom left", "left bottom": return 225
            case "top left", "left top": return 315
            default: return nil
            }
        }
        guard let (value, unit) = numberAndUnit(text), unit == "deg", value.isFinite else { return nil }
        return value
    }

    /// `#112233` or `#112233 40%`.
    private static func stop(_ part: String) -> (ThemeColor, Double?)? {
        let text = part.trimmedText
        // Split from the back: the color can hold spaces itself
        // (`rgb(0 0 0)`), the position always stands at the end. It is split
        // at any whitespace, not only at a space - a tab between the color and
        // the position means the same thing.
        if let space = text.lastIndex(where: \.isWhitespace), text.hasSuffix("%") {
            let tail = String(text[text.index(after: space)...]).trimmedText
            if let (value, unit) = numberAndUnit(tail), unit == "%", value.isFinite,
               let color = self.color(String(text[..<space])) {
                return (color, value / 100)
            }
            return nil
        }
        guard let color = self.color(text) else { return nil }
        return (color, nil)
    }

    private static func hex(_ digits: String) -> ThemeColor? {
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        let characters = Array(digits)
        func part(_ position: Int, short: Bool) -> Double {
            if short {
                let value = characters[position].hexDigitValue ?? 0
                return Double(value * 16 + value) / 255
            }
            let high = characters[position * 2].hexDigitValue ?? 0
            let low = characters[position * 2 + 1].hexDigitValue ?? 0
            return Double(high * 16 + low) / 255
        }
        switch characters.count {
        case 3, 4:
            return ThemeColor(red: part(0, short: true), green: part(1, short: true), blue: part(2, short: true),
                              alpha: characters.count == 4 ? part(3, short: true) : 1)
        case 6, 8:
            return ThemeColor(red: part(0, short: false), green: part(1, short: false), blue: part(2, short: false),
                              alpha: characters.count == 8 ? part(3, short: false) : 1)
        default:
            return nil
        }
    }

    /// Commas, spaces and the slash before the opacity are all allowed - both
    /// spellings of CSS.
    private static func arguments(_ inside: String) -> [String] {
        inside
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "/", with: " / ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func rgb(_ inside: String) -> ThemeColor? {
        let parts = arguments(inside)
        let values = parts.filter { $0 != "/" }
        guard values.count == 3 || values.count == 4 else { return nil }
        var channels: [Double] = []
        for value in values.prefix(3) {
            guard let (number, unit) = numberAndUnit(value) else { return nil }
            switch unit {
            case "": channels.append(number / 255)
            case "%": channels.append(number / 100)
            default: return nil
            }
        }
        var alpha = 1.0
        if values.count == 4 {
            guard let value = alphaValue(values[3]) else { return nil }
            alpha = value
        }
        return ThemeColor(red: channels[0], green: channels[1], blue: channels[2], alpha: alpha)
    }

    private static func hsl(_ inside: String) -> ThemeColor? {
        let values = arguments(inside).filter { $0 != "/" }
        guard values.count == 3 || values.count == 4 else { return nil }
        guard let (hueValue, hueUnit) = numberAndUnit(values[0]), hueUnit == "" || hueUnit == "deg",
              let (saturation, saturationUnit) = numberAndUnit(values[1]),
              saturationUnit == "%" || saturationUnit == "",
              let (lightness, lightnessUnit) = numberAndUnit(values[2]),
              lightnessUnit == "%" || lightnessUnit == "" else { return nil }
        var alpha = 1.0
        if values.count == 4 {
            guard let value = alphaValue(values[3]) else { return nil }
            alpha = value
        }
        let hue = ((hueValue.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 360
        let s = min(max(saturation / 100, 0), 1)
        let l = min(max(lightness / 100, 0), 1)
        guard s > 0 else { return ThemeColor(red: l, green: l, blue: l, alpha: alpha) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func channel(_ offset: Double) -> Double {
            var t = hue + offset
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return ThemeColor(red: channel(1.0 / 3), green: channel(0), blue: channel(-1.0 / 3), alpha: alpha)
    }

    private static func alphaValue(_ text: String) -> Double? {
        guard let (number, unit) = numberAndUnit(text) else { return nil }
        switch unit {
        case "": return number
        case "%": return number / 100
        default: return nil
        }
    }

    /// The basic color names. Not the whole CSS list on purpose: what stands
    /// here holds forever, and a short list is easier to keep than 148 names.
    ///
    private static let named: [String: ThemeColor] = [
        "transparent": .clear,
        "black": ThemeColor(hex: 0x000000),
        "silver": ThemeColor(hex: 0xC0C0C0),
        "gray": ThemeColor(hex: 0x808080),
        "grey": ThemeColor(hex: 0x808080),
        "white": ThemeColor(hex: 0xFFFFFF),
        "maroon": ThemeColor(hex: 0x800000),
        "red": ThemeColor(hex: 0xFF0000),
        "purple": ThemeColor(hex: 0x800080),
        "fuchsia": ThemeColor(hex: 0xFF00FF),
        "magenta": ThemeColor(hex: 0xFF00FF),
        "green": ThemeColor(hex: 0x008000),
        "lime": ThemeColor(hex: 0x00FF00),
        "olive": ThemeColor(hex: 0x808000),
        "yellow": ThemeColor(hex: 0xFFFF00),
        "navy": ThemeColor(hex: 0x000080),
        "blue": ThemeColor(hex: 0x0000FF),
        "teal": ThemeColor(hex: 0x008080),
        "aqua": ThemeColor(hex: 0x00FFFF),
        "cyan": ThemeColor(hex: 0x00FFFF),
        "orange": ThemeColor(hex: 0xFFA500),
    ]

    // MARK: - Numbers

    public static func number(_ raw: String, unit: ThemeUnit) -> Double? {
        guard let (value, suffix) = numberAndUnit(raw.trimmedText) else { return nil }
        switch unit {
        case .points:
            // px and pt are the same: the shell works in points.
            return suffix == "" || suffix == "px" || suffix == "pt" ? value : nil
        case .ratio:
            if suffix == "" { return value }
            return suffix == "%" ? value / 100 : nil
        case .scalar:
            return suffix == "" ? value : nil
        }
    }

    /// The number and the unit, strictly by hand: `Double("nan")`,
    /// `Double("inf")` and `Double("0x1p2")` would be valid and have no
    /// business in a color or a window width.
    private static func numberAndUnit(_ text: String) -> (Double, String)? {
        var digits = ""
        var index = text.startIndex
        if index < text.endIndex, text[index] == "+" || text[index] == "-" {
            digits.append(text[index])
            index = text.index(after: index)
        }
        var sawDigit = false
        while index < text.endIndex, text[index].isASCIIDigit {
            digits.append(text[index])
            index = text.index(after: index)
            sawDigit = true
        }
        if index < text.endIndex, text[index] == "." {
            digits.append(".")
            index = text.index(after: index)
            while index < text.endIndex, text[index].isASCIIDigit {
                digits.append(text[index])
                index = text.index(after: index)
                sawDigit = true
            }
        }
        guard sawDigit, let value = Double(digits), value.isFinite else { return nil }
        let unit = String(text[index...]).trimmedText.lowercased()
        guard unit == "" || unit == "px" || unit == "pt" || unit == "%" || unit == "deg" else { return nil }
        return (value, unit)
    }

    // MARK: - Text, files, yes/no

    /// Either a string in quotes (then without them) or the text as it stands
    /// - font families are often written without them.
    public static func plainText(_ raw: String) -> String {
        let text = quoted(raw) ?? raw.trimmedText
        var result = ""
        var lastWasSpace = false
        for character in text {
            // Control characters and breaks would tear labels apart.
            let isSpace = character.isWhitespace || character.isNewline
            if character.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }), !isSpace {
                continue
            }
            if isSpace {
                if !lastWasSpace, !result.isEmpty { result.append(" ") }
                lastWasSpace = true
                continue
            }
            lastWasSpace = false
            result.append(character)
        }
        return result.trimmedText
    }

    public static func file(_ raw: String) -> String? {
        let text = raw.trimmedText
        if text.lowercased() == "none" { return "" }
        if text.lowercased().hasPrefix("url("), text.hasSuffix(")") {
            let inside = String(text.dropFirst(4).dropLast()).trimmedText
            if inside.isEmpty { return "" }
            return quoted(inside) ?? inside
        }
        // A plain string counts too - `url()` is only the long-winded
        // spelling.
        return quoted(text)
    }

    public static func flag(_ raw: String) -> Bool? {
        switch raw.trimmedText.lowercased() {
        case "true", "yes", "on", "1": true
        case "false", "no", "off", "0": false
        default: nil
        }
    }

    /// The content when the whole text is a single string in quotes -
    /// otherwise `nil`.
    private static func quoted(_ raw: String) -> String? {
        let text = raw.trimmedText
        guard let first = text.first, first == "\"" || first == "'", text.count >= 2 else { return nil }
        var result = ""
        var index = text.index(after: text.startIndex)
        while index < text.endIndex {
            let character = text[index]
            if character == "\\" {
                let next = text.index(after: index)
                guard next < text.endIndex else { return nil }
                result.append(text[next])
                index = text.index(after: next)
                continue
            }
            if character == first {
                // Only when nothing comes after it was it a single string.
                // `"a", "b"` is a list and stays raw.
                return text.index(after: index) == text.endIndex ? result : nil
            }
            result.append(character)
            index = text.index(after: index)
        }
        return nil
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
