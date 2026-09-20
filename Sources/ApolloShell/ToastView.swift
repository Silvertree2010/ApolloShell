import ApolloShellCore
import SwiftUI

/// Caelestia's motion for the toasts (Toasts.qml).
enum ToastMotion {
    /// DefaultSpatial: 500 ms, cubic-bezier(0.38, 1.21, 0.22, 1), slightly
    /// overshooting - appearing, size, moving up, getting out of the way.
    static let spatial = Animation.shellSpatial
    /// DefaultEffects: 200 ms, cubic-bezier(0.34, 0.8, 0.34, 1) - fading out.
    static let effects = Animation.timingCurve(0.34, 0.8, 0.34, 1, duration: 0.2)

    /// A new toast: opacity and size from 0 to 1, both on the space curve
    /// (Caelestia: initAnim, `from: 0`, the middle as the origin). Worked out
    /// instead of stored: AnyTransition is not Sendable.
    static var appear: AnyTransition {
        AnyTransition.opacity.combined(with: .scale(scale: 0)).animation(spatial)
    }

    /// Away - a click, the time is up or a new one pushed it out: opacity to 0
    /// in 200 ms, size to 0.7 in 500 ms. When one that was pushed out moves
    /// back up, the same runs backwards (Caelestia: the behaviors on opacity
    /// and scale).
    static var fade: AnyTransition {
        AnyTransition.opacity.animation(effects)
            .combined(with: AnyTransition.scale(scale: 0.7).animation(spatial))
    }

    static func transition(for entry: ToastEntry) -> AnyTransition {
        .asymmetric(insertion: entry.hasBeenHidden ? fade : appear, removal: fade)
    }
}

/// The colors per kind in Apple tones. Caelestia colors the area, the chip and
/// the border (successContainer/success, secondary/secondaryContainer,
/// errorContainer/error); here the chip carries the full color, the glass only
/// a breath of it, and "Info" stays neutral as in Caelestia (surface, the chip
/// surfaceContainerHigh).
enum ToastPalette {
    /// The colors come out of the theme when one holds - otherwise, as before,
    /// out of the system colors (`ShellStyle` decides that).
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

    /// Without a theme white on the colored tile, as before; with a theme the
    /// text color on accent areas out of the theme.
    static func symbol(_ kind: ToastKind, _ style: ShellStyle = .standard) -> AnyShapeStyle {
        guard accent(kind, style) != nil else { return AnyShapeStyle(.secondary) }
        return AnyShapeStyle(style.color(.onAccent) ?? Color.white)
    }

    /// The tint of the glass.
    static func tint(_ kind: ToastKind, _ style: ShellStyle = .standard) -> Color? {
        accent(kind, style)?.opacity(0.22)
    }

    /// A 1 pt border in the color of the kind, 30 % (Caelestia: `Qt.alpha(..., 0.3)`).
    static func border(_ kind: ToastKind, _ style: ShellStyle = .standard) -> Color {
        accent(kind, style)?.opacity(0.3) ?? Color.primary.opacity(0.08)
    }
}

/// The stack: the newest at the bottom, older ones above it, 8 apart. Fills
/// the whole window, and the stack sticks to the bottom (plus `lift` above the
/// open utilities panel).
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
        // Moving up and getting out of the way: the space curve (Caelestia:
        // Behavior on anchors.bottomMargin).
        .animation(ToastMotion.spatial, value: visible.map(\.id))
        .animation(ToastMotion.spatial, value: toaster.lift)
    }
}

/// One toast (Caelestia: ToastItem.qml): the symbol chip on the left, the
/// title and the message on the right, both on one line with "..." - that is
/// why they are all the same height and the stack can be worked out without
/// measuring.
///
/// The measurements out of Caelestia, carried over to the font of this app:
/// radius 16, margin 8 top and bottom and 12 at the sides, 12 between the
/// chip and the text. The chip is symbol + 16 with radius 16 there; here 40.
struct ToastCard: View {
    static let chip: CGFloat = 40
    static let chipRadius: CGFloat = 12
    static let radius: CGFloat = 16

    let entry: ToastEntry

    @Environment(\.shellStyle) private var style

    var body: some View {
        let radius = style.toastRadius(Self.radius)
        HStack(spacing: 12) {
            // Theme: icons/toast-info.png and the three siblings.
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
                    // Caelestia: the message at 80 % opacity.
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
        // With a theme, the theme colors the toast; glass only when the theme
        // allows it (`--apollo-glass`).
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
        .accessibilityHint("Click to Dismiss")
    }
}
