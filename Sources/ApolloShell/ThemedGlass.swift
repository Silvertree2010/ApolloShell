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
        let look = NSApp.effectiveAppearance
        let dark = look.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let style = ThemeStore.shared?.style(dark: dark) ?? .standard
        let r = style.panelRadius(fallbackRadius)
        if glass.cornerRadius != r { glass.cornerRadius = r }
        if glass.style != .clear { glass.style = .clear }

        content.wantsLayer = true
        previous?.removeFromSuperlayer()
        content.layer?.backgroundColor = nil
        let fv = GlassFill.of(content)
        guard style.paintsPanel else {
            fv.color = NSColor.windowBackgroundColor.withAlphaComponent(GlassLook.fill)
            return nil
        }
        fv.color = nil

        guard let gradient = style.value(ThemeGradientToken.panel), !gradient.isEmpty else {
            if let color = style.value(ThemeColorToken.panel) {
                fv.color = NSColor(color).withAlphaComponent(style.panelOpacity)
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
        fv.layer?.addSublayer(layer)
        layer.frame = fv.bounds
        return layer
    }
}

enum GlassLook {
    static let fill: Double = 0.85
}

final class GlassFill: NSView {
    var color: NSColor? { didSet { needsDisplay = true } }

    static func of(_ v: NSView) -> GlassFill {
        if let f = v.subviews.first as? GlassFill { return f }
        let f = GlassFill(frame: v.bounds)
        f.autoresizingMask = [.width, .height]
        v.addSubview(f, positioned: .below, relativeTo: nil)
        return f
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        var c: CGColor?
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance { c = color?.cgColor }
        layer?.backgroundColor = c
    }

    override func hitTest(_ p: NSPoint) -> NSView? { nil }
}

final class GlassContentView: NSView {
    var onAppearance: () -> Void = {}

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearance()
    }
}
