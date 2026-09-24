import SwiftUI
import AppKit
import ApolloStyle

struct TextStyle {
    var font: Font
    var size: CGFloat
    var color: Color
    var tracking: CGFloat
    var lineSpacing: CGFloat
    var alignment: TextAlignment
    var frameAlignment: Alignment

    init(_ style: ComputedStyle) {
        size = StyleValues.points(style["font-size"]) ?? 13
        font = StyleFonts.font(style, size: size)
        if case .color(let value)? = style["color"] {
            color = StyleValues.color(value)
        } else {
            color = .primary
        }
        tracking = StyleValues.points(style["letter-spacing"]) ?? 0
        switch style["line-height"] {
        case .number(let factor)?: lineSpacing = max(0, (factor - 1) * size * 0.8)
        case .length(let length)? where length.unit == .points: lineSpacing = max(0, length.value - size * 1.2)
        default: lineSpacing = 0
        }
        switch StyleValues.keyword(style["text-align"]) {
        case "center": alignment = .center; frameAlignment = .center
        case "end": alignment = .trailing; frameAlignment = .trailing
        default: alignment = .leading; frameAlignment = .leading
        }
    }
}

enum StyleFonts {
    static func font(_ style: ComputedStyle, size: CGFloat) -> Font {
        let weight = self.weight(style["font-weight"])
        var font: Font
        let families: [String]
        if case .fontFamilies(let list)? = style["font-family"] { families = list } else { families = ["system-ui"] }
        font = .system(size: size, weight: weight)
        for family in families {
            if let found = self.family(family, size: size, weight: weight) {
                font = found
                break
            }
        }
        if StyleValues.keyword(style["font-style"]) == "italic" { font = font.italic() }
        if StyleValues.keyword(style["font-variant-numeric"]) == "tabular-nums" { font = font.monospacedDigit() }
        return font
    }

    static func family(_ name: String, size: CGFloat, weight: Font.Weight) -> Font? {
        switch name.lowercased() {
        case "system-ui", "-apple-system", "sans-serif": return .system(size: size, weight: weight)
        case "ui-monospace", "monospace": return .system(size: size, weight: weight, design: .monospaced)
        case "ui-rounded": return .system(size: size, weight: weight, design: .rounded)
        case "ui-serif", "serif": return .system(size: size, weight: weight, design: .serif)
        default:
            guard NSFont(name: name, size: size) != nil else { return nil }
            return .custom(name, fixedSize: size).weight(weight)
        }
    }

    static func weight(_ value: CSSValue?) -> Font.Weight {
        let number: Double
        switch value {
        case .number(let found)?: number = found
        case .keyword("bold")?: number = 700
        default: number = 400
        }
        switch number {
        case ..<150: return .ultraLight
        case ..<250: return .thin
        case ..<350: return .light
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        case ..<850: return .heavy
        default: return .black
        }
    }
}
