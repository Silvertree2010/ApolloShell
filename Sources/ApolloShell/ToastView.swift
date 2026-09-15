import ApolloShellCore
import SwiftUI

/// Caelestias Bewegungen der Kurzmeldungen (Toasts.qml).
enum ToastMotion {
    /// DefaultSpatial: 500 ms, cubic-bezier(0.38, 1.21, 0.22, 1), leicht
    /// ueberschiessend - Aufgehen, Groesse, Nachruecken, Ausweichen.
    static let spatial = Animation.timingCurve(0.38, 1.21, 0.22, 1, duration: 0.5)
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
    static func accent(_ kind: ToastKind) -> Color? {
        switch kind {
        case .info: nil
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }

    static func chip(_ kind: ToastKind) -> AnyShapeStyle {
        accent(kind).map { AnyShapeStyle($0) } ?? AnyShapeStyle(Color.primary.opacity(0.10))
    }

    static func symbol(_ kind: ToastKind) -> AnyShapeStyle {
        accent(kind) == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.white)
    }

    /// Toenung des Glases.
    static func tint(_ kind: ToastKind) -> Color? {
        accent(kind)?.opacity(0.22)
    }

    /// 1 pt Rand in der Farbe der Art, 30 % (Caelestia: `Qt.alpha(..., 0.3)`).
    static func border(_ kind: ToastKind) -> Color {
        accent(kind)?.opacity(0.3) ?? Color.primary.opacity(0.08)
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ToastPalette.symbol(entry.kind))
                .frame(width: Self.chip, height: Self.chip)
                .background(ToastPalette.chip(entry.kind), in: .rect(cornerRadius: Self.chipRadius))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(entry.title)
                    .font(.system(size: 14, weight: .medium))
                Text(entry.message)
                    .font(.system(size: 12))
                    // Caelestia: Nachricht mit 80 % Deckkraft.
                    .opacity(0.8)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: CGFloat(ToastLayout.width), height: CGFloat(ToastLayout.itemHeight))
        .toastGlass(tint: ToastPalette.tint(entry.kind), cornerRadius: Self.radius)
        .overlay {
            RoundedRectangle(cornerRadius: Self.radius)
                .strokeBorder(ToastPalette.border(entry.kind), lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: Self.radius))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Klicken zum Schliessen")
    }
}
