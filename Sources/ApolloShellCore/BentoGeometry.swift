import Foundation

/// Geometrie der Bento-Seiten: gueltige Lage, Einrasten, Massstab. Reine
/// Funktionen in Referenzpunkten (Seite 839 x 392, `DashboardGeometry`).
/// Keine Zellen: Caelestias Masse (130, 250, 275, 110 ...) passen in kein
/// gleichmaessiges Raster, Ordnung kommt vom Einrasten.
public enum BentoGeometry {
    public static let pageWidth = DashboardGeometry.width
    public static let pageHeight = DashboardGeometry.height
    /// Mindestabstand zweier Widgets, Caelestias Rasterabstand.
    public static let spacing = DashboardGeometry.spacing
    /// Naeher als das: das Widget springt aufs Ziel.
    public static let snapDistance: Double = 8

    // MARK: Gueltig

    public static func isInside(_ frame: WidgetFrame) -> Bool {
        frame.x >= 0 && frame.y >= 0 && frame.maxX <= pageWidth && frame.maxY <= pageHeight
    }

    /// Naeher als `spacing` in beiden Achsen, Ueberlappung eingeschlossen.
    /// Genau `spacing` Abstand ist erlaubt; schraeg versetzt zaehlt nur, wenn
    /// beide Achsen zu nah sind.
    public static func tooClose(_ a: WidgetFrame, _ b: WidgetFrame) -> Bool {
        a.x < b.maxX + spacing && b.x < a.maxX + spacing
            && a.y < b.maxY + spacing && b.y < a.maxY + spacing
    }

    public static func isValid(_ frame: WidgetFrame, kind: WidgetKind, others: [WidgetFrame]) -> Bool {
        isInside(frame) && kind.allows(width: frame.width, height: frame.height)
            && !others.contains { tooClose(frame, $0) }
    }

    // MARK: Massstab

    /// Breite des 14-Zoll-MacBooks: dort Faktor 1, alles wie vor 0.2.
    public static let referenceScreenWidth: Double = 1512
    public static let automaticRange: ClosedRange<Double> = 0.85...1.5
    /// Der Regler in Nexus.
    public static let userScaleRange: ClosedRange<Double> = 0.7...1.5

    public static func clampedUserScale(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, userScaleRange.lowerBound), userScaleRange.upperBound)
    }

    /// Massstab fuer einen Bildschirm: Automatik nach Breite mal Regler,
    /// hoechstens so gross, dass `contentHeight` (das ganze Dashboard in
    /// Referenzgroesse, mit Seitenleiste oben) in `availableHeight` passt.
    public static func scale(screenWidth: Double, availableHeight: Double, contentHeight: Double,
                             userScale: Double) -> Double {
        let automatic = min(max(screenWidth / referenceScreenWidth, automaticRange.lowerBound), automaticRange.upperBound)
        let wanted = automatic * clampedUserScale(userScale)
        guard contentHeight > 0 else { return wanted }
        return min(wanted, availableHeight / contentHeight)
    }
}
