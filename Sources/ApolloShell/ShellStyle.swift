import AppKit
import ApolloShellCore
import SwiftUI

/// Die Werte eines Themes, fertig fuer SwiftUI.
///
/// Zwei Regeln halten das hier zusammen:
///
/// 1. **Was das Theme nicht nennt, bleibt, wie macOS es zeichnet.** `Theme`
///    liefert nur Werte aus der Datei; fehlt einer, gilt hier die Systemfarbe,
///    Material oder das eingebaute Mass. Ohne Theme (`Theme.standard`) fehlt
///    alles - die Shell sieht aus wie ohne Themes.
/// 2. **Kein Zugriff kann scheitern.** Der Kern hat jeden Wert schon geprueft
///    und geklemmt; hier wird nur noch umgerechnet.
struct ShellStyle: Equatable {
    let theme: Theme
    let dark: Bool

    /// Das eingebaute Aussehen: genau die Shell ohne Theme.
    static let standard = ShellStyle(theme: .standard, dark: false)

    /// Der Wert des Themes in diesem Erscheinungsbild, `nil`, wenn es ihn
    /// nicht nennt.
    func value<Kind>(_ token: ThemeToken<Kind>) -> Kind.Value? {
        theme.value(token, dark: dark)
    }

    // MARK: - Farben

    /// Die Farbe des Themes, `nil`, wenn es sie nicht nennt.
    func color(_ token: ThemeColorToken) -> Color? {
        value(token).map(Color.init)
    }

    /// Die Farbe des Themes, sonst `fallback` - auch ein hierarchischer Stil
    /// wie `.primary`, der auf Glas lebendig bleibt (eine feste Farbe tut
    /// das nicht).
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

    /// Schrift auf Akzentflaechen, wenn das Theme dazu etwas sagt: seine
    /// eigene, oder die Vorgabe lesbar gemacht auf seinem Akzent. Sonst `nil`.
    var themeOnAccent: Color? { theme.readableColor(.onAccent, dark: dark).map(Color.init) }

    /// Schrift auf Akzentflaechen; ohne Angabe im Theme wie macOS
    /// (`Color.onAccent`, passend zum Akzent des Systems).
    var onAccent: Color { themeOnAccent ?? .onAccent }

    // MARK: - Flaechen

    /// Fuellung einer Flaeche: der Verlauf, wenn das Theme einen setzt, sonst
    /// die Farbe daneben, sonst `fallback`.
    private func fill(_ colorToken: ThemeColorToken, _ gradientToken: ThemeGradientToken,
                      fallback: some ShapeStyle) -> AnyShapeStyle {
        if let gradient = value(gradientToken), !gradient.isEmpty {
            return AnyShapeStyle(ShellStyle.linear(gradient))
        }
        return paint(colorToken, or: fallback)
    }

    /// Faerbt das Theme diese Flaeche ueberhaupt? Nennt es weder Farbe noch
    /// Verlauf, bleibt die Flaeche, wie die Shell sie zeichnet - also Glas
    /// und Material statt einer Ersatzfarbe.
    private func paints(_ colorToken: ThemeColorToken, _ gradientToken: ThemeGradientToken) -> Bool {
        value(colorToken) != nil || value(gradientToken) != nil
    }

    var paintsBar: Bool { paints(.bar, .bar) }
    var paintsPanel: Bool { paints(.panel, .panel) }
    var paintsCard: Bool { paints(.card, .card) }
    var paintsToast: Bool { paints(.toast, .toast) }
    var paintsSurface: Bool { paints(.surface, .surface) }
    var paintsLauncherHighlight: Bool { paints(.launcherHighlight, .launcherHighlight) }

    /// Hintergrund der Leiste, mit Deckkraft aus dem Theme.
    var barFill: AnyShapeStyle {
        let opacity = value(.barOpacity) ?? 1
        if let gradient = value(ThemeGradientToken.bar), !gradient.isEmpty {
            return AnyShapeStyle(ShellStyle.linear(gradient).opacity(opacity))
        }
        guard let bar = color(.bar) else { return AnyShapeStyle(Color.clear) }
        return AnyShapeStyle(bar.opacity(opacity))
    }

    /// Wie deckend ein Panel ist (`--apollo-panel-opacity`).
    var panelOpacity: Double { value(.panelOpacity) ?? 1 }

    /// Deckt die Leiste vollstaendig? Dann braucht es nichts dahinter.
    var barIsOpaque: Bool { (value(.barOpacity) ?? 1) >= 1 }

    /// Flaeche von Fenstern und Listen (`--apollo-surface-color`, mit
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

    /// Ein Verlauf des Themes als SwiftUI-Verlauf. Der Winkel folgt CSS:
    /// 0 Grad nach oben, 90 Grad nach rechts.
    static func linear(_ gradient: ThemeGradient) -> LinearGradient {
        let stops = gradient.stops.map {
            Gradient.Stop(color: Color($0.color), location: $0.position)
        }
        // Die Richtung rechnet der Kern (`ThemeGradient.points`, geprueft).
        let points = gradient.points
        return LinearGradient(
            stops: stops,
            startPoint: UnitPoint(x: points.start.x, y: points.start.y),
            endPoint: UnitPoint(x: points.end.x, y: points.end.y)
        )
    }

    // MARK: - Masse

    /// Eine Laenge des Themes, `nil`, wenn es sie nicht nennt.
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

    /// Staerke der Umrandung; 0 heisst: keine.
    func borderWidth(_ fallback: CGFloat) -> CGFloat { length(.borderWidth) ?? fallback }

    /// Umrandung einer Flaeche, oder nichts, wenn das Theme keine Breite
    /// nennt oder sie auf 0 stellt.
    @ViewBuilder
    func border<S: InsettableShape>(_ shape: S) -> some View {
        if let width = length(.borderWidth), width > 0 {
            shape.strokeBorder(border, lineWidth: width)
        }
    }

    /// Wie stark Schatten unter Flaechen sind.
    func shadowOpacity(_ fallback: Double) -> Double {
        if value(.shadows) == false { return 0 }
        return value(.shadowOpacity) ?? fallback
    }

    // MARK: - Schrift

    /// Schriftart des Themes, sonst die Systemschrift.
    ///
    /// Ein Name, den es auf diesem Mac nicht gibt, faellt still auf die
    /// Systemschrift zurueck - ein Theme aus dem Netz darf die Shell nicht
    /// unlesbar machen.
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let family = (value(.fontFamily) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let scaled = size * fontScale
        guard !family.isEmpty, NSFont(name: family, size: scaled) != nil else {
            return .system(size: scaled, weight: weight)
        }
        return .custom(family, fixedSize: scaled).weight(weight)
    }

    /// Wie stark die Schriftgroessen des Themes von den eingebauten abweichen.
    /// 13 pt ist die Systemgroesse, an der die Shell gebaut ist.
    private var fontScale: CGFloat {
        guard let size = value(.fontSize), size > 0 else { return 1 }
        return CGFloat(size) / 13
    }

    // MARK: - Symbole

    /// Das Bild, das das Theme fuer dieses Symbol mitbringt - `nil`, wenn
    /// keines dabei ist.
    func iconFile(_ id: String) -> URL? {
        theme.icon(id)
    }

    // MARK: - Schalter

    /// Darf sich etwas bewegen? Ein Theme kann Bewegung abstellen; die
    /// Systemeinstellung "Bewegung reduzieren" hat dennoch Vorrang, die
    /// fragen die Ansichten selbst ab.
    var animations: Bool { value(.animations) ?? true }

    /// Darf Liquid Glass benutzt werden?
    var glass: Bool { value(.glass) ?? true }

    /// Wie schnell Bewegungen laufen; 1 ist die eingebaute Geschwindigkeit.
    var animationSpeed: Double { value(.animationSpeed) ?? 1 }

    /// Eine Dauer, vom Theme gestreckt oder gekuerzt. Ohne Bewegung: 0.
    func duration(_ seconds: Double) -> Double {
        guard animations else { return 0 }
        let speed = animationSpeed
        return speed > 0 ? seconds / speed : seconds
    }
}

extension NSColor {
    /// Eine Themefarbe als AppKit-Farbe, im festen sRGB-Raum.
    convenience init(_ color: ThemeColor) {
        self.init(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

extension Color {
    /// Eine Themefarbe als SwiftUI-Farbe, im festen sRGB-Raum - genau die
    /// Werte, die in der Datei stehen.
    init(_ color: ThemeColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}

// MARK: - In der Umgebung

private struct ShellStyleKey: EnvironmentKey {
    static let defaultValue = ShellStyle.standard
}

extension EnvironmentValues {
    /// Der Stil des gewaehlten Themes. Vorgabe ist die Shell ohne Theme -
    /// eine Ansicht ohne `shellTheme` sieht also aus wie immer.
    var shellStyle: ShellStyle {
        get { self[ShellStyleKey.self] }
        set { self[ShellStyleKey.self] = newValue }
    }
}

/// Der Stil der laufenden Shell im gewuenschten Erscheinungsbild.
///
/// Ansichten benutzen das so:
/// ```swift
/// @Environment(\.colorScheme) private var scheme
/// private var style: ShellStyle { ShellTheme.style(scheme) }
/// ```
@MainActor
enum ShellTheme {
    static func style(_ scheme: ColorScheme) -> ShellStyle {
        ThemeStore.shared?.style(dark: scheme == .dark) ?? .standard
    }
}

/// Legt den Stil in die Umgebung, im Erscheinungsbild dieses Fensters.
///
/// Gehoert an die Wurzel jedes Fensters der Shell. Weil das Erscheinungsbild
/// (hell/dunkel) erst hier bekannt ist, wird der Stil in einer Ansicht
/// aufgeloest und nicht im Speicher.
private struct ShellThemeScope: ViewModifier {
    let store: ThemeStore
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let style = store.style(dark: scheme == .dark)
        content
            .environment(\.shellStyle, style)
            // Steuerelemente (Schalter, Schieber, Auswahl) folgen dem Theme,
            // ohne dass jede Ansicht es selbst setzen muss.
            .tint(style.accent)
    }
}

extension View {
    /// Faerbt den Hintergrund eines Fensters oder einer Liste nach dem Theme.
    ///
    /// Nennt das Theme keine Flaeche, bleibt alles, wie macOS es zeichnet -
    /// also auch das Glas der Seitenleiste von Nexus. Sonst wird der eigene
    /// Hintergrund der Rollflaeche ausgeblendet, er laege darueber.
    @ViewBuilder
    func themedWindowBackground(_ style: ShellStyle) -> some View {
        if style.paintsSurface {
            scrollContentBackground(.hidden)
                .background(style.surfaceFill)
        } else {
            self
        }
    }

    /// An die Wurzel eines Fensters: setzt `tint` und den Stil in der Umgebung.
    func shellTheme(_ store: ThemeStore? = ThemeStore.shared) -> some View {
        modifier(OptionalShellThemeScope(store: store))
    }
}

/// Ohne Speicher (Bildproben, Vorschauen) bleibt alles wie es ist.
private struct OptionalShellThemeScope: ViewModifier {
    let store: ThemeStore?

    func body(content: Content) -> some View {
        if let store {
            AnyView(content.modifier(ShellThemeScope(store: store)))
        } else {
            AnyView(content)
        }
    }
}
