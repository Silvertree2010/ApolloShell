import SwiftUI

/// A card with a slightly offset surface on the glass - in the dashboard,
/// on the "Performance" tab, in weather, and in media.
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
    /// A card's surface. With a theme, `--apollo-card-color` (or the
    /// gradient next to it) colors it, `--apollo-card-radius` rounds it, and
    /// there's a border only if the theme names a width. Without a theme, a
    /// light veil, as everywhere in the shell.
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
