import SwiftUI
import AppKit
import ApolloStyle

enum StyleValues {
    static func color(_ color: CSSColor, current: Color = .primary) -> Color {
        switch color {
        case let .rgba(red, green, blue, alpha):
            Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
        case let .system(name, alpha):
            systemColor(name).opacity(alpha)
        case .currentColor:
            current
        }
    }

    static func systemColor(_ name: String) -> Color {
        switch name {
        case "-apple-system-label": .primary
        case "-apple-system-secondary-label": .secondary
        case "-apple-system-tertiary-label": Color(nsColor: .tertiaryLabelColor)
        case "-apple-system-quaternary-label": Color(nsColor: .quaternaryLabelColor)
        case "-apple-system-separator": Color(nsColor: .separatorColor)
        case "-apple-system-control-accent": Color(nsColor: .controlAccentColor)
        case "-apple-system-window-background": Color(nsColor: .windowBackgroundColor)
        case "-apple-system-control-background": Color(nsColor: .controlBackgroundColor)
        case "-apple-system-text-background": Color(nsColor: .textBackgroundColor)
        case "-apple-system-selected-content-background": Color(nsColor: .selectedContentBackgroundColor)
        case "-apple-system-red": .red
        case "-apple-system-orange": .orange
        case "-apple-system-yellow": .yellow
        case "-apple-system-green": .green
        case "-apple-system-mint": .mint
        case "-apple-system-teal": .teal
        case "-apple-system-cyan": .cyan
        case "-apple-system-blue": .blue
        case "-apple-system-indigo": .indigo
        case "-apple-system-purple": .purple
        case "-apple-system-pink": .pink
        case "-apple-system-brown": .brown
        case "-apple-system-gray": .gray
        default: .primary
        }
    }

    static func length(_ value: CSSValue?) -> CSSLength? {
        if case .length(let length)? = value { return length }
        return nil
    }

    static func points(_ value: CSSValue?) -> CGFloat? {
        guard let length = length(value), length.unit == .points else { return nil }
        return CGFloat(length.value)
    }

    static func percent(_ value: CSSValue?) -> CGFloat? {
        guard let length = length(value), length.unit == .percent else { return nil }
        return CGFloat(length.value / 100)
    }

    static func gradient(_ gradient: ApolloStyle.LinearGradient) -> SwiftUI.LinearGradient {
        let radians = gradient.angleDegrees * .pi / 180
        let dx = sin(radians) / 2, dy = -cos(radians) / 2
        return SwiftUI.LinearGradient(
            stops: gradient.stops.map { .init(color: color($0.color), location: $0.position ?? 0) },
            startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy), endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }

    static func glass(_ variant: GlassVariant, tint: CSSColor?) -> Glass {
        let base: Glass = variant == .clear ? .clear : .regular
        return tint.map { base.tint(color($0)) } ?? base
    }

    static func material(_ thickness: MaterialThickness) -> Material {
        switch thickness {
        case .ultraThin: .ultraThinMaterial
        case .thin: .thinMaterial
        case .regular: .regularMaterial
        case .thick: .thickMaterial
        case .ultraThick: .ultraThickMaterial
        case .bar: .bar
        }
    }

    static func fills(_ value: CSSValue?) -> Bool {
        guard let length = length(value) else { return false }
        return length.unit == .percent && length.value >= 100
    }

    static func sides(_ value: CSSValue?) -> EdgeInsets {
        guard case .lengths(let list)? = value, !list.isEmpty else { return EdgeInsets() }
        func side(_ index: Int) -> CGFloat {
            let item = list[min(index, list.count - 1)]
            return item.unit == .points ? CGFloat(item.value) : 0
        }
        switch list.count {
        case 1: return EdgeInsets(top: side(0), leading: side(0), bottom: side(0), trailing: side(0))
        case 2: return EdgeInsets(top: side(0), leading: side(1), bottom: side(0), trailing: side(1))
        case 3: return EdgeInsets(top: side(0), leading: side(1), bottom: side(2), trailing: side(1))
        default: return EdgeInsets(top: side(0), leading: side(3), bottom: side(2), trailing: side(1))
        }
    }

    static func radius(_ value: CSSValue?) -> CGFloat {
        guard case .lengths(let list)? = value, let first = list.first, first.unit == .points else { return 0 }
        return CGFloat(first.value)
    }

    static func gap(_ value: CSSValue?) -> CGFloat {
        switch value {
        case .length(let length)?: length.unit == .points ? CGFloat(length.value) : 0
        case .lengths(let list)?: list.first.map { $0.unit == .points ? CGFloat($0.value) : 0 } ?? 0
        default: 0
        }
    }

    static func number(_ value: CSSValue?) -> Double? {
        if case .number(let number)? = value { return number }
        return nil
    }

    static func keyword(_ value: CSSValue?) -> String? {
        if case .keyword(let word)? = value { return word }
        return nil
    }

    static func horizontal(_ value: CSSValue?) -> HorizontalAlignment {
        switch keyword(value) {
        case "start": .leading
        case "end": .trailing
        default: .center
        }
    }

    static func vertical(_ value: CSSValue?) -> VerticalAlignment {
        switch keyword(value) {
        case "start": .top
        case "end": .bottom
        default: .center
        }
    }

    static func translation(_ value: CSSValue?) -> CGSize {
        guard case .transform(let operations)? = value else { return .zero }
        var size = CGSize.zero
        for case let .translate(x, y) in operations {
            size.width += x
            size.height += y
        }
        return size
    }

    static func fadeEdges(_ value: CSSValue?) -> Double? {
        guard let length = length(value) else { return nil }
        switch length.unit {
        case .percent: return length.value / 100
        default: return nil
        }
    }
}
