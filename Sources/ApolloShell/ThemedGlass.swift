import AppKit
import ApolloShellCore

/// Faerbt ein `NSGlassEffectView` nach dem Theme.
///
/// Drei Fenster der Shell liegen in so einem Glas: die Kantenfenster
/// (Dashboard, Utilities), der Launcher und das Sitzungsmenue. Ohne Theme
/// bleibt es das Glas von macOS; mit Theme liegt die Panelfarbe darunter.
///
/// Als Ebene und nicht als Toenung des Glases: Eine Ebenenfarbe gilt sofort,
/// eine Toenung erst beim naechsten Zeichnen - gesehen am Dashboard, das bis
/// zum ersten Klick durchsichtig blieb. Die Ebene liegt unter dem ganzen
/// Glas, nicht nur unter der Ansicht, sonst bliebe der Streifen daneben
/// (Platz fuer Menueleiste und Notch) frei und es gaebe eine Naht.
@MainActor
enum ThemedGlass {
    /// Setzt Ecke und Flaeche. Gibt die angelegte Verlaufsebene zurueck, die
    /// der Aufrufer beim naechsten Mal wieder mitgibt, damit sie ersetzt und
    /// nicht gestapelt wird.
    @discardableResult
    static func apply(to glass: NSGlassEffectView?, fallbackRadius: CGFloat,
                      previous: CAGradientLayer? = nil) -> CAGradientLayer? {
        guard let glass, let content = glass.contentView else { return nil }
        let look = glass.effectiveAppearance
        let dark = look.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let style = ThemeStore.shared?.style(dark: dark) ?? .standard
        let r = style.panelRadius(fallbackRadius)
        if glass.cornerRadius != r { glass.cornerRadius = r }
        if glass.style != .clear { glass.style = .clear }

        content.wantsLayer = true
        previous?.removeFromSuperlayer()
        content.layer?.backgroundColor = nil
        guard style.paintsPanel else {
            var c: CGColor?
            look.performAsCurrentDrawingAppearance {
                c = NSColor.windowBackgroundColor.withAlphaComponent(GlassLook.fill).cgColor
            }
            content.layer?.backgroundColor = c
            return nil
        }

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

enum GlassLook {
    static let fill: Double = 0.85
}

final class GlassContentView: NSView {
    var onAppearance: () -> Void = {}

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearance()
    }
}
