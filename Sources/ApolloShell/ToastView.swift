import ApolloShellCore
import SwiftUI

/// Caelestias Bewegungen der Kurzmeldungen (Toasts.qml).
enum ToastMotion {
    /// DefaultSpatial: 500 ms, cubic-bezier(0.38, 1.21, 0.22, 1), leicht
    /// ueberschiessend - Aufgehen, Groesse, Nachruecken, Ausweichen.
    static let spatial = Animation.shellSpatial
    /// DefaultEffects: 200 ms, cubic-bezier(0.34, 0.8, 0.34, 1) - Ausblenden.
    static let effects = Animation.timingCurve(0.34, 0.8, 0.34, 1, duration: 0.2)

    /// Neue Meldung: Deckkraft und Groesse von 0 auf 1, beides auf der
    /// Raumkurve (Caelestia: initAnim, `from: 0`, Mitte als Ursprung).
    /// Berechnet statt gespeichert: AnyTransition ist nicht Sendable.
    static var appear: AnyTransition {
        AnyTransition.opacity.combined(with: .scale(scale: 0)).animation(spatial)
    }

    /// Weg - Klick, Zeit um oder von einer neuen verdraengt: Deckkraft in
    /// 200 ms auf 0, Groesse in 500 ms auf 0.7. Rueckt eine verdraengte
    /// wieder nach, laeuft dasselbe rueckwaerts (Caelestia: die Behaviors
    /// auf opacity und scale).
    static var fade: AnyTransition {
        AnyTransition.opacity.animation(effects)
            .combined(with: AnyTransition.scale(scale: 0.7).animation(spatial))
    }

    static func transition(for entry: ToastEntry) -> AnyTransition {
        .asymmetric(insertion: entry.hasBeenHidden ? fade : appear, removal: fade)
    }
}

/// Farben je Art in Apple-Tonen. Caelestia faerbt Flaeche, Chip und Rand
/// (successContainer/success, secondary/secondaryContainer,
/// errorContainer/error); hier traegt der Chip die volle Farbe, das Glas nur
/// einen Hauch davon, und "Info" bleibt neutral wie bei Caelestia
/// (surface, Chip surfaceContainerHigh).
enum ToastPalette {
    /// Die Farben kommen aus dem Theme, wenn eines gilt - sonst wie bisher
    /// aus den Systemfarben (`ShellStyle` entscheidet das).
    static func accent(_ kind: ToastKind, _ style: ShellStyle = .standard) -> Color? {
        switch kind {
        case .info: nil
        case .success: style.success
        case .warning: style.warning
        case .error: style.danger
        }
    }

    static func chip(_ kind: ToastKind, _ style: ShellStyle = .standard) -> AnyShapeStyle {
        accent(kind, style).map { AnyShapeStyle($0) } ?? AnyShapeStyle(Color.primary.opacity(0.10))
    }

    /// Ohne Theme weiss auf der farbigen Kachel, wie bisher; mit Theme die
    /// Schrift auf Akzentflaechen aus dem Theme.
    static func symbol(_ kind: ToastKind, _ style: ShellStyle = .standard) -> AnyShapeStyle {
        guard accent(kind, style) != nil else { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(style.color(.onAccent) ?? Color.white)
    }

    /// Toenung des Glases.
    static func tint(_ kind: ToastKind, _ style: ShellStyle = .standard) -> Color? {
        accent(kind, style)?.opacity(0.22)
    }

    /// 1 pt Rand in der Farbe der Art, 30 % (Caelestia: `Qt.alpha(..., 0.3)`).
    static func border(_ kind: ToastKind, _ style: ShellStyle = .standard) -> Color {
        accent(kind, style)?.opacity(0.3) ?? Color.primary.opacity(0.08)
    }
}

/// Der Stapel: neueste unten, aeltere darueber, 8 Abstand. Fuellt das
/// ganze Fenster, der Stapel klebt unten (plus `lift` ueber dem offenen
/// Utilities-Panel).
struct ToastStackView: View {
    let toaster: Toaster
    let overscan: CGFloat

    var body: some View {
        let visible = toaster.visible
        VStack(spacing: CGFloat(ToastLayout.spacing)) {
            ForEach(Array(visible.reversed())) { entry in
                ToastCard(entry: entry)
                    .onTapGesture { toaster.dismiss(entry.id) }
                    .transition(ToastMotion.transition(for: entry))
            }
        }
        .padding(.bottom, toaster.lift)
        .padding(overscan)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // Nachruecken und Ausweichen: Raumkurve (Caelestia: Behavior on
        // anchors.bottomMargin).
        .animation(ToastMotion.spatial, value: visible.map(\.id))
        .animation(ToastMotion.spatial, value: toaster.lift)
    }
}

/// Eine Meldung (Caelestia: ToastItem.qml): Symbol-Chip links, Titel und
/// Nachricht rechts, beides einzeilig mit "..." - deshalb sind alle gleich
/// hoch und der Stapel ist ohne Messen berechenbar.
///
/// Masse aus Caelestia auf die Schrift dieser App umgelegt: Radius 16,
/// Rand 8 oben/unten und 12 seitlich, 12 zwischen Chip und Text. Der Chip
/// ist dort Symbol + 16 mit Radius 16; hier 40 mit Radius 12, passend zu
/// Titel 14 und Unterzeile 12 wie die Karten im Utilities-Panel.
struct ToastCard: View {
    static let chip: CGFloat = 40
    static let chipRadius: CGFloat = 12
    static let radius: CGFloat = 16

    let entry: ToastEntry

    @Environment(\.shellStyle) private var style

    var body: some View {
        let radius = style.toastRadius(Self.radius)
        HStack(spacing: 12) {
            // Theme: icons/toast-info.png und die drei Geschwister.
            ThemedIcon(entry.kind.iconID, fallback: entry.symbol)
                .font(style.font(size: 18, weight: .semibold))
                .frame(width: 20, height: 20)
                .foregroundStyle(ToastPalette.symbol(entry.kind, style))
                .frame(width: Self.chip, height: Self.chip)
                .background(ToastPalette.chip(entry.kind, style),
                            in: .rect(cornerRadius: style.controlRadius(Self.chipRadius)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(entry.title)
                    .font(style.font(size: 14, weight: .medium))
                Text(entry.message)
                    .font(style.font(size: 12))
                    // Caelestia: Nachricht mit 80 % Deckkraft.
                    .opacity(0.8)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(style.paint(.toastText, or: .primary))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: CGFloat(ToastLayout.width), height: CGFloat(ToastLayout.itemHeight))
        // Mit Theme faerbt das Theme die Meldung; Glas nur, wenn das Theme es
        // erlaubt (`--apollo-glass`).
        .background {
            if style.paintsToast {
                RoundedRectangle(cornerRadius: radius).fill(style.toastFill)
            }
        }
        .toastGlass(tint: ToastPalette.tint(entry.kind, style),
                    cornerRadius: radius,
                    enabled: style.glass)
        .overlay {
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(ToastPalette.border(entry.kind, style), lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: radius))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Klicken zum Schliessen")
    }
}
