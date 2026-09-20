import AppKit
import ApolloShellCore

/// Colors an `NSGlassEffectView` by the theme.
///
/// Three windows of the shell lie in such glass: the edge windows (dashboard,
/// utilities), the launcher and the session menu. Without a theme it stays the
/// glass of macOS; with a theme the panel color lies below it.
///
/// As a layer and not as a tint of the glass: a layer color holds right away,
/// a tint only on the next drawing - seen on the dashboard, which stayed
/// transparent until the first click. The layer lies under the whole glass,
/// not only under the view, otherwise the strip beside it (room for the menu
/// bar and the notch) would stay free and there would be a seam.
@MainActor
enum ThemedGlass {
    /// Sets the corner and the area. Hands back the gradient layer it created,
    /// which the caller brings along next time, so that it is replaced and not
    /// stacked.
    @discardableResult
    static func apply(to glass: NSGlassEffectView?, fallbackRadius: CGFloat,
                      previous: CAGradientLayer? = nil) -> CAGradientLayer? {
        guard let glass, let content = glass.contentView else { return nil }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let style = ThemeStore.shared?.style(dark: dark) ?? .standard
        glass.cornerRadius = style.panelRadius(fallbackRadius)

        content.wantsLayer = true
        previous?.removeFromSuperlayer()
        content.layer?.backgroundColor = nil
        guard style.paintsPanel else { return nil }

        guard let gradient = style.value(ThemeGradientToken.panel), !gradient.isEmpty else {
            if let color = style.value(ThemeColorToken.panel) {
                content.layer?.backgroundColor = NSColor(color).withAlphaComponent(style.panelOpacity).cgColor
            }
            return nil
        }
        let layer = CAGradientLayer()
        layer.frame = content.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.colors = gradient.stops.map { NSColor($0.color).cgColor }
        layer.locations = gradient.stops.map { NSNumber(value: $0.position) }
        let points = gradient.points
        layer.startPoint = CGPoint(x: points.start.x, y: points.start.y)
        layer.endPoint = CGPoint(x: points.end.x, y: points.end.y)
        layer.opacity = Float(style.panelOpacity)
        content.layer?.insertSublayer(layer, at: 0)
        return layer
    }
}
