import ApolloShellCore
import SwiftUI

/// Zustand der Lautstaerke-Anzeige.
@MainActor
@Observable
final class OSDModel {
    var volume: Float = 0
    var muted = false
    /// Waehrend sich der Wert aendert (und 500 ms danach) zeigt der Griff die
    /// Prozentzahl statt des Symbols - wie Caelestia.
    var moving = false
    var hovered = false {
        didSet { if hovered != oldValue { onHoverChanged(hovered) } }
    }
    @ObservationIgnored var onDrag: (Float) -> Void = { _ in }
    @ObservationIgnored var onHoverChanged: (Bool) -> Void = { _ in }
}

/// OSD wie Caelestia (modules/osd): ein senkrechter Regler 30 x 150,
/// Innenabstand 16, Radius des Panels 28 (Masse aus dem Quellcode). Nur die
/// Lautstaerke: Helligkeit des internen Bildschirms laesst sich auf Apple
/// Silicon ohne private Schnittstellen nicht lesen, das Mikrofon ist bei
/// Caelestia ab Werk aus.
struct OSDView: View {
    @Bindable var model: OSDModel

    static let sliderWidth: CGFloat = 30
    static let sliderHeight: CGFloat = 150
    static let padding: CGFloat = 16
    /// Caelestia: Reglerbreite + padding.large + 2 x 3 px Mittenversatz.
    static var width: CGFloat { sliderWidth + padding + 6 }
    static var height: CGFloat { sliderHeight + 2 * padding }

    var body: some View {
        VolumeSlider(model: model)
            .frame(width: Self.sliderWidth, height: Self.sliderHeight)
            .frame(width: Self.width, height: Self.height)
            // Maus auf der Anzeige haelt sie offen (Caelestia: hovered).
            .background(HoverTracker { model.hovered = $0 })
    }
}

private struct VolumeSlider: View {
    let model: OSDModel

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let value = model.muted ? 0 : CGFloat(min(max(model.volume, 0), 1))
            // Mindestens so hoch wie der Griff, sonst verschwindet er unten.
            let fill = max(w, value * h)
            // Caelestia: Fuellung "StandardLarge" 600 ms, Kurve (0.2, 0, 0, 1).
            let fillAnimation = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.6)

            ZStack(alignment: .bottom) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: fill)
                    .animation(fillAnimation, value: fill)

                handle(diameter: w - 4)
                    .padding(.bottom, 2)
                    .offset(y: -(fill - w))
                    .animation(fillAnimation, value: fill)
            }
            .contentShape(.capsule)
            // Ziehen setzt die Lautstaerke (nur auf ausdruecklichen Wunsch).
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                model.onDrag(Float(1 - min(max(drag.location.y / h, 0), 1)))
            })
        }
        .accessibilityElement()
        .accessibilityLabel("Lautstärke \(VolumeGlyphs.percent(model.volume)) Prozent")
    }

    private func handle(diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
            Group {
                if model.moving {
                    Text("\(VolumeGlyphs.percent(model.muted ? 0 : model.volume))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Image(systemName: VolumeGlyphs.symbol(volume: model.volume, muted: model.muted))
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(Color.black.opacity(0.8))
            .transition(.opacity)
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.2), value: model.moving)
    }
}
