import AppKit
import ApolloShellCore
import SwiftUI

/// Die Werte eines Themes, fertig fuer SwiftUI.
///
/// Zwei Regeln halten das hier zusammen:
///
/// 1. **Ohne Theme aendert sich nichts.** Ist keines gewaehlt (`isThemed`
///    falsch), liefert jeder Zugriff genau das, was die Shell vorher benutzt
///    hat: die Systemfarben von macOS, Material, die eingebauten Masse. Die
///    Vorgaben des Katalogs sind den Systemfarben nur nachempfunden - wer
///    kein Theme hat, soll aber keinen Unterschied sehen.
/// 2. **Kein Zugriff kann scheitern.** Der Kern hat jeden Wert schon geprueft
///    und geklemmt; hier wird nur noch umgerechnet.
struct ShellStyle: Equatable {
    let theme: Theme
    let dark: Bool
    let isThemed: Bool

    /// Das eingebaute Aussehen: genau die Shell ohne Theme.
    static let standard = ShellStyle(theme: .standard, dark: false, isThemed: false)

    // MARK: - Farben

    /// Nennt das gewaehlte Theme dieses Token?
    ///
    /// Nur was in der Datei steht, wird uebernommen. Die Vorgaben im
    /// Verzeichnis sind dem Aussehen der Shell nur nachempfunden - wer sie
    /// auf ein nicht genanntes Token anwendete, aenderte damit doch etwas.
    private func declares(_ name: String) -> Bool {
        isThemed && theme.declares(name)
    }

    /// Eine Themefarbe, oder die Systemfarbe, solange das Theme sie nicht nennt.
    private func color(_ token: ThemeColorToken, fallback: Color) -> Color {
        declares(token.name) ? Color(theme.color(token, dark: dark)) : fallback
    }

    var accent: Color { color(.accent, fallback: .accentColor) }
    var secondaryAccent: Color { color(.secondaryAccent, fallback: Color(nsColor: .systemIndigo)) }
    var text: Color { color(.text, fallback: .primary) }
    var secondaryText: Color { color(.secondaryText, fallback: .secondary) }
    var mutedText: Color { color(.mutedText, fallback: Color(nsColor: .tertiaryLabelColor)) }
    var link: Color { color(.link, fallback: .accentColor) }
    var separator: Color { color(.separator, fallback: Color(nsColor: .separatorColor)) }
    var border: Color { color(.border, fallback: Color(nsColor: .separatorColor)) }
    var selection: Color { color(.selection, fallback: .accentColor.opacity(0.18)) }
    var hover: Color { color(.hover, fallback: Color.primary.opacity(0.08)) }
    var success: Color { color(.success, fallback: .green) }
    var warning: Color { color(.warning, fallback: .orange) }
    var danger: Color { color(.danger, fallback: .red) }
    var barText: Color { color(.barText, fallback: .primary) }
    var barIcon: Color { color(.barIcon, fallback: .primary) }
    var dockIndicator: Color { color(.dockIndicator, fallback: .primary.opacity(0.6)) }
    var launcherHighlight: Color { color(.launcherHighlight, fallback: .accentColor.opacity(0.18)) }
    var toastText: Color { color(.toastText, fallback: .primary) }
    var card: Color { color(.card, fallback: Color(nsColor: .windowBackgroundColor)) }
    var surface: Color { color(.surface, fallback: Color(nsColor: .windowBackgroundColor)) }

    /// Die Schrift auf Akzentflaechen. Ohne Theme wie bisher berechnet
    /// (`Color.onAccent`), mit Theme das Token - der Kern haelt es lesbar.
    var onAccent: Color { isThemed ? Color(theme.color(.onAccent, dark: dark)) : .onAccent }

    // MARK: - Flaechen

    /// Fuellung einer Flaeche: der Verlauf, wenn das Theme einen setzt, sonst
    /// die Farbe daneben.
    private func fill(_ colorToken: ThemeColorToken, _ gradientToken: ThemeGradientToken,
                      fallback: Color) -> AnyShapeStyle {
        let gradient = theme.gradient(gradientToken, dark: dark)
        if declares(gradientToken.name), !gradient.isEmpty {
            return AnyShapeStyle(ShellStyle.linear(gradient))
        }
        guard declares(colorToken.name) else { return AnyShapeStyle(fallback) }
        return AnyShapeStyle(Color(theme.color(colorToken, dark: dark)))
    }

    /// Faerbt das Theme diese Flaeche ueberhaupt? Nennt es weder Farbe noch
    /// Verlauf, bleibt die Flaeche, wie die Shell sie zeichnet - also Glas
    /// und Material statt einer Ersatzfarbe.
    private func paints(_ colorToken: ThemeColorToken, _ gradientToken: ThemeGradientToken) -> Bool {
        declares(colorToken.name) || declares(gradientToken.name)
    }

    var paintsBar: Bool { paints(.bar, .bar) }
    var paintsPanel: Bool { paints(.panel, .panel) }
    var paintsCard: Bool { paints(.card, .card) }
    var paintsToast: Bool { paints(.toast, .toast) }
    var paintsSurface: Bool { paints(.surface, .surface) }
    var paintsLauncherHighlight: Bool { paints(.launcherHighlight, .launcherHighlight) }

    /// Nennt das Theme dieses einzelne Token? Fuer Stellen, die kein
    /// Flaechenpaar aus Farbe und Verlauf haben (Schriftfarbe, Punkt im Dock).
    func declaresColor(_ token: ThemeColorToken) -> Bool { declares(token.name) }
    func declaresNumber(_ token: ThemeNumberToken) -> Bool { declares(token.name) }

    /// Hintergrund der Leiste, mit Deckkraft aus dem Theme.
    var barFill: AnyShapeStyle {
        guard isThemed else { return AnyShapeStyle(Color.clear) }
        let opacity = declares(ThemeNumberToken.barOpacity.name) ? theme.number(.barOpacity, dark: dark) : 1
        let gradient = theme.gradient(.bar, dark: dark)
        if gradient.isEmpty {
            return AnyShapeStyle(Color(theme.color(.bar, dark: dark)).opacity(opacity))
        }
        return AnyShapeStyle(ShellStyle.linear(gradient).opacity(opacity))
    }

    /// Wie deckend ein Panel ist (`--apollo-panel-opacity`).
    var panelOpacity: Double {
        declares(ThemeNumberToken.panelOpacity.name) ? theme.number(.panelOpacity, dark: dark) : 1
    }

    /// Deckt die Leiste vollstaendig? Dann braucht es nichts dahinter.
    var barIsOpaque: Bool {
        guard isThemed else { return false }
        return !declares(ThemeNumberToken.barOpacity.name) || theme.number(.barOpacity, dark: dark) >= 1
    }

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
        fill(.accent, .accent, fallback: .accentColor)
    }

    var toastFill: AnyShapeStyle {
        fill(.toast, .toast, fallback: Color(nsColor: .windowBackgroundColor))
    }

    var launcherHighlightFill: AnyShapeStyle {
        fill(.launcherHighlight, .launcherHighlight, fallback: .accentColor.opacity(0.18))
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

    /// Eine Laenge des Themes, oder das eingebaute Mass.
    private func length(_ token: ThemeNumberToken, fallback: CGFloat) -> CGFloat {
        declares(token.name) ? CGFloat(theme.number(token, dark: dark)) : fallback
    }

    func cornerRadius(_ fallback: CGFloat) -> CGFloat { length(.cornerRadius, fallback: fallback) }
    func controlRadius(_ fallback: CGFloat) -> CGFloat { length(.controlRadius, fallback: fallback) }
    func panelRadius(_ fallback: CGFloat) -> CGFloat { length(.panelRadius, fallback: fallback) }
    func cardRadius(_ fallback: CGFloat) -> CGFloat { length(.cardRadius, fallback: fallback) }
    func toastRadius(_ fallback: CGFloat) -> CGFloat { length(.toastRadius, fallback: fallback) }
    func barRadius(_ fallback: CGFloat) -> CGFloat { length(.barRadius, fallback: fallback) }
    func barPadding(_ fallback: CGFloat) -> CGFloat { length(.barPadding, fallback: fallback) }
    func barItemSpacing(_ fallback: CGFloat) -> CGFloat { length(.barItemSpacing, fallback: fallback) }
    func panelPadding(_ fallback: CGFloat) -> CGFloat { length(.panelPadding, fallback: fallback) }
    func spacing(_ fallback: CGFloat) -> CGFloat { length(.spacing, fallback: fallback) }
    func barWidth(_ fallback: CGFloat) -> CGFloat { length(.barWidth, fallback: fallback) }
    func dockIconSize(_ fallback: CGFloat) -> CGFloat { length(.dockIconSize, fallback: fallback) }
    func dockSpacing(_ fallback: CGFloat) -> CGFloat { length(.dockSpacing, fallback: fallback) }
    func launcherRowHeight(_ fallback: CGFloat) -> CGFloat { length(.launcherRowHeight, fallback: fallback) }

    /// Staerke der Umrandung; 0 heisst: keine.
    func borderWidth(_ fallback: CGFloat) -> CGFloat { length(.borderWidth, fallback: fallback) }

    /// Umrandung einer Flaeche, oder nichts, wenn kein Theme gilt oder das
    /// Theme die Breite auf 0 stellt.
    @ViewBuilder
    func border<S: InsettableShape>(_ shape: S) -> some View {
        if isThemed, borderWidth(0) > 0 {
            shape.strokeBorder(border, lineWidth: borderWidth(0))
        }
    }

    /// Wie stark Schatten unter Flaechen sind.
    func shadowOpacity(_ fallback: Double) -> Double {
        if declares(ThemeFlagToken.shadows.name), !theme.flag(.shadows, dark: dark) { return 0 }
        guard declares(ThemeNumberToken.shadowOpacity.name) else { return fallback }
        return theme.number(.shadowOpacity, dark: dark)
    }

    // MARK: - Schrift

    /// Schriftart des Themes, sonst die Systemschrift.
    ///
    /// Ein Name, den es auf diesem Mac nicht gibt, faellt still auf die
    /// Systemschrift zurueck - ein Theme aus dem Netz darf die Shell nicht
    /// unlesbar machen.
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard isThemed else { return .system(size: size, weight: weight) }
        let family = declares(ThemeTextToken.fontFamily.name)
            ? theme.text(.fontFamily, dark: dark).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let scaled = size * fontScale
        guard !family.isEmpty, NSFont(name: family, size: scaled) != nil else {
            return .system(size: scaled, weight: weight)
        }
        return .custom(family, fixedSize: scaled).weight(weight)
    }

    /// Wie stark die Schriftgroessen des Themes von den eingebauten abweichen.
    /// 13 pt ist die Systemgroesse, an der die Shell gebaut ist.
    private var fontScale: CGFloat {
        guard declares(ThemeNumberToken.fontSize.name) else { return 1 }
        let size = theme.number(.fontSize, dark: dark)
        return size > 0 ? CGFloat(size) / 13 : 1
    }

    // MARK: - Symbole

    /// Das Bild, das das Theme fuer dieses Symbol mitbringt - `nil`, wenn
    /// keines dabei ist.
    func iconFile(_ id: String) -> URL? {
        guard isThemed else { return nil }
        return theme.icon(id)
    }

    // MARK: - Schalter

    /// Darf sich etwas bewegen? Ein Theme kann Bewegung abstellen; die
    /// Systemeinstellung "Bewegung reduzieren" hat dennoch Vorrang, die
    /// fragen die Ansichten selbst ab.
    var animations: Bool { declares(ThemeFlagToken.animations.name) ? theme.flag(.animations, dark: dark) : true }

    /// Darf Liquid Glass benutzt werden?
    var glass: Bool { declares(ThemeFlagToken.glass.name) ? theme.flag(.glass, dark: dark) : true }

    /// Wie schnell Bewegungen laufen; 1 ist die eingebaute Geschwindigkeit.
    var animationSpeed: Double {
        declares(ThemeNumberToken.animationSpeed.name) ? theme.number(.animationSpeed, dark: dark) : 1
    }

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
    /// Ohne Theme bleibt alles, wie macOS es zeichnet - also auch das Glas
    /// der Seitenleiste von Nexus. Mit Theme wird der eigene Hintergrund der
    /// Rollflaeche ausgeblendet, sonst laege er darueber.
    @ViewBuilder
    func themedWindowBackground(_ style: ShellStyle) -> some View {
        if style.isThemed {
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
