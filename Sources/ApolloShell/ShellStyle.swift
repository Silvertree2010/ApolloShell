import AppKit
import ApolloShellCore
import SwiftUI

/// The values of a theme, ready for SwiftUI.
///
/// Two rules hold this together:
///
/// 1. **What the theme does not name stays as macOS draws it.** `Theme`
///    only supplies values from the file; if one is missing, the system
///    color, material, or built-in measurement applies here. Without a
///    theme (`Theme.standard`) everything is missing - the shell looks as
///    if there were no themes.
/// 2. **No access can fail.** The core has already validated and clamped
///    every value; here it is only converted.
struct ShellStyle: Equatable {
    let theme: Theme
    let dark: Bool

    /// The built-in look: exactly the shell without a theme.
    static let standard = ShellStyle(theme: .standard, dark: false)

    /// The value of the theme in this appearance, `nil` if it does not
    /// name it.
    func value<Kind>(_ token: ThemeToken<Kind>) -> Kind.Value? {
        theme.value(token, dark: dark)
    }

    // MARK: - Colors

    /// The color of the theme, `nil` if it does not name it.
    func color(_ token: ThemeColorToken) -> Color? {
        value(token).map(Color.init)
    }

    /// The color of the theme, otherwise `fallback` - also a hierarchical
    /// style like `.primary`, which stays alive on glass (a fixed color
    /// does not).
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

    /// Text color on accent areas, if the theme says something about it:
    /// its own, or the default made readable on its accent. Otherwise
    /// `nil`.
    var themeOnAccent: Color? { theme.readableColor(.onAccent, dark: dark).map(Color.init) }

    /// Text color on accent areas; without a theme value, like macOS
    /// (`Color.onAccent`, matching the system accent).
    var onAccent: Color { themeOnAccent ?? .onAccent }

    // MARK: - Surfaces

    /// Fill of a surface: the gradient, if the theme sets one, otherwise
    /// the color next to it, otherwise `fallback`.
    private func fill(_ colorToken: ThemeColorToken, _ gradientToken: ThemeGradientToken,
                      fallback: some ShapeStyle) -> AnyShapeStyle {
        if let gradient = value(gradientToken), !gradient.isEmpty {
            return AnyShapeStyle(ShellStyle.linear(gradient))
        }
        return paint(colorToken, or: fallback)
    }

    /// Does the theme color this surface at all? If it names neither a
    /// color nor a gradient, the surface stays as the shell draws it -
    /// that is, glass and material instead of a substitute color. A
    /// gradient of `none` colors nothing: without a color next to it the
    /// surface would otherwise stay empty (the bar would be invisible).
    private func paints(_ colorToken: ThemeColorToken, _ gradientToken: ThemeGradientToken) -> Bool {
        value(colorToken) != nil || value(gradientToken).map { !$0.isEmpty } == true
    }

    var paintsBar: Bool { paints(.bar, .bar) }
    var paintsPanel: Bool { paints(.panel, .panel) }
    var paintsCard: Bool { paints(.card, .card) }
    var paintsToast: Bool { paints(.toast, .toast) }
    var paintsSurface: Bool { paints(.surface, .surface) }
    var paintsLauncherHighlight: Bool { paints(.launcherHighlight, .launcherHighlight) }

    /// Background of the bar, with opacity from the theme.
    var barFill: AnyShapeStyle {
        let opacity = value(.barOpacity) ?? 1
        if let gradient = value(ThemeGradientToken.bar), !gradient.isEmpty {
            return AnyShapeStyle(ShellStyle.linear(gradient).opacity(opacity))
        }
        guard let bar = color(.bar) else { return AnyShapeStyle(Color.clear) }
        return AnyShapeStyle(bar.opacity(opacity))
    }

    /// How opaque a panel is (`--apollo-panel-opacity`).
    var panelOpacity: Double { value(.panelOpacity) ?? 1 }

    /// Does the bar cover completely? Then nothing is needed behind it.
    var barIsOpaque: Bool { (value(.barOpacity) ?? 1) >= 1 }

    /// Surface of windows and lists (`--apollo-surface-color`, with
    /// `--apollo-surface-gradient`).
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

    /// A gradient of the theme as a SwiftUI gradient. The angle follows
    /// CSS: 0 degrees upward, 90 degrees to the right.
    static func linear(_ gradient: ThemeGradient) -> LinearGradient {
        let stops = gradient.stops.map {
            Gradient.Stop(color: Color($0.color), location: $0.position)
        }
        // The core computes the direction (`ThemeGradient.points`, validated).
        let points = gradient.points
        return LinearGradient(
            stops: stops,
            startPoint: UnitPoint(x: points.start.x, y: points.start.y),
            endPoint: UnitPoint(x: points.end.x, y: points.end.y)
        )
    }

    // MARK: - Measurements

    /// A length of the theme, `nil` if it does not name it.
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

    /// Border width; 0 means: none.
    func borderWidth(_ fallback: CGFloat) -> CGFloat { length(.borderWidth) ?? fallback }

    /// Border of a surface, or nothing if the theme names no width or
    /// sets it to 0.
    @ViewBuilder
    func border<S: InsettableShape>(_ shape: S) -> some View {
        if let width = length(.borderWidth), width > 0 {
            shape.strokeBorder(border, lineWidth: width)
        }
    }

    /// How strong shadows under surfaces are.
    func shadowOpacity(_ fallback: Double) -> Double {
        if value(.shadows) == false { return 0 }
        return value(.shadowOpacity) ?? fallback
    }

    // MARK: - Typography

    /// Font of the theme, otherwise the system font.
    ///
    /// A name that does not exist on this Mac silently falls back to the
    /// system font - a theme from the internet must not make the shell
    /// unreadable.
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let family = (value(.fontFamily) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let scaled = size * fontScale
        guard !family.isEmpty, NSFont(name: family, size: scaled) != nil else {
            return .system(size: scaled, weight: weight)
        }
        return .custom(family, fixedSize: scaled).weight(weight)
    }

    /// How much the theme's font sizes deviate from the built-in ones.
    /// 13 pt is the system size the shell is built around.
    private var fontScale: CGFloat {
        guard let size = value(.fontSize), size > 0 else { return 1 }
        return CGFloat(size) / 13
    }

    // MARK: - Symbols

    /// The image the theme brings for this symbol - `nil` if none is
    /// included.
    func iconFile(_ id: String) -> URL? {
        theme.icon(id)
    }

    // MARK: - Switches

    /// May something move? A theme can turn off motion; the system
    /// setting "Reduce Motion" still takes precedence, the views query
    /// it themselves.
    var animations: Bool { value(.animations) ?? true }

    /// May Liquid Glass be used?
    var glass: Bool { value(.glass) ?? true }

    /// Should images a theme brings for symbols be tinted?
    ///
    /// `--apollo-icon-style`: `monochrome` tints them like the glyph they
    /// replace (that is, following `--apollo-bar-icon-color` and
    /// relatives); `colorful` and the default `auto` show them as they
    /// are painted. The default thus changes nothing for existing sets.
    var tintsThemeIcons: Bool { value(.iconStyle) == "monochrome" }

    /// How fast animations run; 1 is the built-in speed.
    var animationSpeed: Double { value(.animationSpeed) ?? 1 }

    /// A duration, stretched or shortened by the theme. Without motion: 0.
    func duration(_ seconds: Double) -> Double {
        guard animations else { return 0 }
        let speed = animationSpeed
        return speed > 0 ? seconds / speed : seconds
    }
}

extension NSColor {
    /// A theme color as an AppKit color, in the fixed sRGB space.
    convenience init(_ color: ThemeColor) {
        self.init(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

extension Color {
    /// A theme color as a SwiftUI color, in the fixed sRGB space - exactly
    /// the values that are in the file.
    init(_ color: ThemeColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}

// MARK: - In the environment

private struct ShellStyleKey: EnvironmentKey {
    static let defaultValue = ShellStyle.standard
}

extension EnvironmentValues {
    /// The style of the chosen theme. Default is the shell without a
    /// theme - a view without `shellTheme` thus looks as it always did.
    var shellStyle: ShellStyle {
        get { self[ShellStyleKey.self] }
        set { self[ShellStyleKey.self] = newValue }
    }
}

/// Puts the style into the environment, in this window's appearance.
///
/// Belongs at the root of every window of the shell (`shellTheme()`).
/// Views read it like this:
/// ```swift
/// @Environment(\.shellStyle) private var style
/// ``` Because the appearance
/// (light/dark) is only known here, the style is resolved in a view and
/// not stored.
private struct ShellThemeScope: ViewModifier {
    let store: ThemeStore
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let style = store.style(dark: scheme == .dark)
        content
            .environment(\.shellStyle, style)
            // Controls (toggles, sliders, pickers) follow the theme,
            // without every view having to set it itself.
            .tint(style.accent)
    }
}

extension View {
    /// Colors the background of a window or a list according to the theme.
    ///
    /// If the theme names no surface, everything stays as macOS draws it
    /// - including the glass of Nexus's sidebar. Otherwise the scroll
    /// area's own background is hidden, it would sit above it.
    @ViewBuilder
    func themedWindowBackground(_ style: ShellStyle) -> some View {
        if style.paintsSurface {
            scrollContentBackground(.hidden)
                .background(style.surfaceFill)
        } else {
            self
        }
    }

    /// At the root of a window: sets `tint` and the style in the
    /// environment. Also before every measurement of a view
    /// (`fittingSize`), otherwise it is measured without the theme's font
    /// and measurements.
    func shellTheme(_ store: ThemeStore? = ThemeStore.shared) -> ModifiedContent<Self, ShellThemeRoot> {
        modifier(ShellThemeRoot(store: store))
    }
}

/// The root from `shellTheme()`. Named type so windows can carry it in
/// their `NSHostingView<...>`. Without storage (image samples, previews)
/// everything stays as it is.
struct ShellThemeRoot: ViewModifier {
    let store: ThemeStore?

    func body(content: Content) -> some View {
        if let store {
            AnyView(content.modifier(ShellThemeScope(store: store)))
        } else {
            AnyView(content)
        }
    }
}
