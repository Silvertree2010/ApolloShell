import AppKit
import ApolloShellCore
import SwiftUI

struct ShellStyle: Equatable {
    let theme: Theme
    let dark: Bool

    static let standard = ShellStyle(theme: .standard, dark: false)

    func value<Kind>(_ token: ThemeToken<Kind>) -> Kind.Value? {
        theme.value(token, dark: dark)
    }

    func color(_ token: ThemeColorToken) -> Color? {
        value(token).map(Color.init)
    }

    func paint(_ token: ThemeColorToken, or fallback: some ShapeStyle) -> AnyShapeStyle {
        color(token).map(AnyShapeStyle.init) ?? AnyShapeStyle(fallback)
    }

    var accent: Color { color(.accent) ?? .accentColor }
    var secondaryAccent: Color { color(.secondaryAccent) ?? Color(nsColor: .systemIndigo) }
    var text: Color { color(.text) ?? .primary }
    var secondaryText: Color { color(.secondaryText) ?? .secondary }
    var mutedText: Color { color(.mutedText) ?? Color(nsColor: .tertiaryLabelColor) }
    var link: Color { color(.link) ?? .accentColor }
    var separator: Color { color(.separator) ?? Color(nsColor: .separatorColor) }
    var border: Color { color(.border) ?? Color(nsColor: .separatorColor) }
    var selection: Color { color(.selection) ?? .accentColor.opacity(0.18) }
    var hover: Color { color(.hover) ?? Color.primary.opacity(0.08) }
    var success: Color { color(.success) ?? .green }
    var warning: Color { color(.warning) ?? .orange }
    var danger: Color { color(.danger) ?? .red }
    var barText: Color { color(.barText) ?? .primary }
    var barIcon: Color { color(.barIcon) ?? .primary }
    var dockIndicator: Color { color(.dockIndicator) ?? .primary.opacity(0.6) }
    var launcherHighlight: Color { color(.launcherHighlight) ?? .accentColor.opacity(0.18) }
    var toastText: Color { color(.toastText) ?? .primary }
    var card: Color { color(.card) ?? Color(nsColor: .windowBackgroundColor) }
    var surface: Color { color(.surface) ?? Color(nsColor: .windowBackgroundColor) }

    var themeOnAccent: Color? { theme.readableColor(.onAccent, dark: dark).map(Color.init) }

    var onAccent: Color { themeOnAccent ?? .onAccent }

    private func fill(_ colorToken: ThemeColorToken, _ gradientToken: ThemeGradientToken,
                      fallback: some ShapeStyle) -> AnyShapeStyle {
        if let gradient = value(gradientToken), !gradient.isEmpty {
            return AnyShapeStyle(ShellStyle.linear(gradient))
        }
        return paint(colorToken, or: fallback)
    }

    private func paints(_ colorToken: ThemeColorToken, _ gradientToken: ThemeGradientToken) -> Bool {
        value(colorToken) != nil || value(gradientToken).map { !$0.isEmpty } == true
    }

    var paintsBar: Bool { paints(.bar, .bar) }
    var paintsPanel: Bool { paints(.panel, .panel) }
    var paintsCard: Bool { paints(.card, .card) }
    var paintsToast: Bool { paints(.toast, .toast) }
    var paintsSurface: Bool { paints(.surface, .surface) }
    var paintsLauncherHighlight: Bool { paints(.launcherHighlight, .launcherHighlight) }

    var barFill: AnyShapeStyle {
        let opacity = value(.barOpacity) ?? 1
        if let gradient = value(ThemeGradientToken.bar), !gradient.isEmpty {
            return AnyShapeStyle(ShellStyle.linear(gradient).opacity(opacity))
        }
        guard let bar = color(.bar) else { return AnyShapeStyle(Color.clear) }
        return AnyShapeStyle(bar.opacity(opacity))
    }

    var panelOpacity: Double { value(.panelOpacity) ?? 1 }

    var barIsOpaque: Bool { (value(.barOpacity) ?? 1) >= 1 }

    var surfaceFill: AnyShapeStyle {
        fill(.surface, .surface, fallback: Color(nsColor: .windowBackgroundColor))
    }

    var panelFill: AnyShapeStyle {
        fill(.panel, .panel, fallback: Color(nsColor: .windowBackgroundColor))
    }

    var cardFill: AnyShapeStyle {
        fill(.card, .card, fallback: Color(nsColor: .windowBackgroundColor))
    }

    var accentFill: AnyShapeStyle {
        fill(.accent, .accent, fallback: Color.accentColor)
    }

    var toastFill: AnyShapeStyle {
        fill(.toast, .toast, fallback: Color(nsColor: .windowBackgroundColor))
    }

    var launcherHighlightFill: AnyShapeStyle {
        fill(.launcherHighlight, .launcherHighlight, fallback: Color.accentColor.opacity(0.18))
    }

    var backgroundFill: AnyShapeStyle {
        fill(.background, .background, fallback: Color(nsColor: .windowBackgroundColor))
    }

    static func linear(_ gradient: ThemeGradient) -> LinearGradient {
        let stops = gradient.stops.map {
            Gradient.Stop(color: Color($0.color), location: $0.position)
        }
        let points = gradient.points
        return LinearGradient(
            stops: stops,
            startPoint: UnitPoint(x: points.start.x, y: points.start.y),
            endPoint: UnitPoint(x: points.end.x, y: points.end.y)
        )
    }

    func length(_ token: ThemeNumberToken) -> CGFloat? {
        value(token).map { CGFloat($0) }
    }

    func cornerRadius(_ fallback: CGFloat) -> CGFloat { length(.cornerRadius) ?? fallback }
    func controlRadius(_ fallback: CGFloat) -> CGFloat { length(.controlRadius) ?? fallback }
    func panelRadius(_ fallback: CGFloat) -> CGFloat { length(.panelRadius) ?? fallback }
    func cardRadius(_ fallback: CGFloat) -> CGFloat { length(.cardRadius) ?? fallback }
    func toastRadius(_ fallback: CGFloat) -> CGFloat { length(.toastRadius) ?? fallback }
    func barRadius(_ fallback: CGFloat) -> CGFloat { length(.barRadius) ?? fallback }
    func barPadding(_ fallback: CGFloat) -> CGFloat { length(.barPadding) ?? fallback }
    func barItemSpacing(_ fallback: CGFloat) -> CGFloat { length(.barItemSpacing) ?? fallback }
    func panelPadding(_ fallback: CGFloat) -> CGFloat { length(.panelPadding) ?? fallback }
    func spacing(_ fallback: CGFloat) -> CGFloat { length(.spacing) ?? fallback }
    func barWidth(_ fallback: CGFloat) -> CGFloat { length(.barWidth) ?? fallback }
    func dockIconSize(_ fallback: CGFloat) -> CGFloat { length(.dockIconSize) ?? fallback }
    func dockSpacing(_ fallback: CGFloat) -> CGFloat { length(.dockSpacing) ?? fallback }
    func launcherRowHeight(_ fallback: CGFloat) -> CGFloat { length(.launcherRowHeight) ?? fallback }

    func borderWidth(_ fallback: CGFloat) -> CGFloat { length(.borderWidth) ?? fallback }

    @ViewBuilder
    func border<S: InsettableShape>(_ shape: S) -> some View {
        if let width = length(.borderWidth), width > 0 {
            shape.strokeBorder(border, lineWidth: width)
        }
    }

    func shadowOpacity(_ fallback: Double) -> Double {
        if value(.shadows) == false { return 0 }
        return value(.shadowOpacity) ?? fallback
    }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let family = (value(.fontFamily) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let scaled = size * fontScale
        guard !family.isEmpty, NSFont(name: family, size: scaled) != nil else {
            return .system(size: scaled, weight: weight)
        }
        return .custom(family, fixedSize: scaled).weight(weight)
    }

    private var fontScale: CGFloat {
        guard let size = value(.fontSize), size > 0 else { return 1 }
        return CGFloat(size) / 13
    }

    func iconFile(_ id: String) -> URL? {
        theme.icon(id)
    }

    var animations: Bool { value(.animations) ?? true }

    var glass: Bool { value(.glass) ?? true }

    var tintsThemeIcons: Bool { value(.iconStyle) == "monochrome" }

    var animationSpeed: Double { value(.animationSpeed) ?? 1 }

    func duration(_ seconds: Double) -> Double {
        guard animations else { return 0 }
        let speed = animationSpeed
        return speed > 0 ? seconds / speed : seconds
    }
}

extension NSColor {
    convenience init(_ color: ThemeColor) {
        self.init(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

extension Color {
    init(_ color: ThemeColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}

private struct ShellStyleKey: EnvironmentKey {
    static let defaultValue = ShellStyle.standard
}

extension EnvironmentValues {
    var shellStyle: ShellStyle {
        get { self[ShellStyleKey.self] }
        set { self[ShellStyleKey.self] = newValue }
    }
}
