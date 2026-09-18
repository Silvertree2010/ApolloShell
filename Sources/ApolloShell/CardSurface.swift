import SwiftUI

/// Karte mit leicht abgesetzter Flaeche auf dem Glas - im Dashboard, im
/// Reiter "Leistung", beim Wetter und bei den Medien.
struct Card<Content: View>: View {
    let radius: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cardSurface(radius: radius)
    }
}

extension View {
    /// Die Flaeche einer Karte. Mit Theme faerbt `--apollo-card-color` (oder
    /// der Verlauf daneben) sie, `--apollo-card-radius` rundet sie, und einen
    /// Rand gibt es nur, wenn das Theme eine Breite nennt. Ohne Theme ein
    /// leichter Schleier, wie ueberall in der Shell.
    func cardSurface(radius: CGFloat) -> some View {
        modifier(CardSurface(radius: radius))
    }
}

private struct CardSurface: ViewModifier {
    let radius: CGFloat
    @Environment(\.shellStyle) private var style

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: style.cardRadius(radius), style: .continuous)
        content
            .background {
                if style.paintsCard {
                    shape.fill(style.cardFill)
                } else {
                    shape.fill(Color.primary.opacity(0.06))
                }
            }
            .overlay { style.border(shape) }
    }
}
