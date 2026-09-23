import ApolloShellCore
import SwiftUI

/// The brightness card in the utilities panel: a heading with the level,
/// below it a sun symbol and the slider - the same shape as the sound
/// card's volume row (`UtilitiesAudioCard.swift`), just without the mute
/// button (there is nothing to mute here) and without the device buttons
/// (there is only one brightness, not a choice of devices).
///
/// Without DisplayServices (`UtilitiesBrightness`, an external non-Apple
/// monitor as the only screen, say) the slider stays disabled and a short
/// note explains why - the card never just disappears, so its spot in
/// Nexus stays predictable.
struct UtilitiesBrightnessCard: View {
    let model: UtilitiesModel
    @Environment(\.shellStyle) private var style

    var body: some View {
        UtilitiesCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(UtilitiesBrightnessText.title)
                        .font(style.font(size: 14, weight: .medium))
                    Spacer(minLength: 8)
                    if let brightness = model.brightness {
                        Text(UtilitiesBrightnessText.level(brightness))
                            .font(style.font(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }
                .lineLimit(1)

                HStack(spacing: 10) {
                    Image(systemName: "sun.max.fill")
                        .font(style.font(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                    UtilitiesBrightnessSlider(model: model)
                }

                // Reserved even when settable, empty and invisible: that
                // way the card is exactly as tall in both states, matching
                // the fixed `UtilitiesMetrics.brightnessHeight`.
                Text(model.brightnessSettable ? "" : UtilitiesBrightnessText.unavailable)
                    .font(style.font(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .opacity(model.brightnessSettable ? 0 : 1)
            }
        }
    }
}

/// A horizontal slider, the same look and gestures as
/// `UtilitiesVolumeSlider` - track 10 % foreground, fill in the accent
/// color, a white knob at the end of the fill.
private struct UtilitiesBrightnessSlider: View {
    static let height: CGFloat = 24
    /// The step for VoiceOver and the arrow keys.
    private static let step: Float = 1.0 / 16

    let model: UtilitiesModel
    @Environment(\.shellStyle) private var style

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let value = CGFloat(min(max(model.brightness ?? 0, 0), 1))
            let fill = h + value * (w - h)

            ZStack(alignment: .leading) {
                Capsule().fill(style.paintsCard ? AnyShapeStyle(style.card) : AnyShapeStyle(Color.primary.opacity(0.10)))
                Capsule()
                    .fill(style.accentFill)
                    .frame(width: fill)
                    .opacity(value > 0 ? 1 : 0)
                Circle()
                    .fill(style.themeOnAccent ?? Color.white)
                    .shadow(color: .black.opacity(style.shadowOpacity(0.25)), radius: 1.5, y: 0.5)
                    .frame(width: h - 4, height: h - 4)
                    .offset(x: fill - h + 2)
            }
            .contentShape(.capsule)
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let position = (drag.location.x - h / 2) / max(w - h, 1)
                model.setBrightness(Float(min(max(position, 0), 1)))
            })
        }
        .frame(height: Self.height)
        .opacity(model.brightnessSettable ? 1 : 0.4)
        .allowsHitTesting(model.brightnessSettable)
        .accessibilityElement()
        .accessibilityLabel(UtilitiesBrightnessText.title)
        .accessibilityValue(model.brightness.map(UtilitiesBrightnessText.level) ?? "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.setBrightness((model.brightness ?? 0) + Self.step)
            case .decrement: model.setBrightness((model.brightness ?? 0) - Self.step)
            @unknown default: break
            }
        }
    }
}
