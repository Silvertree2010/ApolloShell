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

    // MARK: Einrasten

    /// Ziehen: je Achse springt das Widget aufs naechste Ziel naeher als
    /// `snapDistance` - Seitenrand, gleiche Flucht wie ein anderes Widget,
    /// oder genau `spacing` daneben. Ohne Ziel bleibt die Achse. Ergebnis
    /// auf ganze Punkte gerundet; ob es passt, sagt `isValid`.
    public static func snapMove(_ proposed: WidgetFrame, others: [WidgetFrame]) -> WidgetFrame {
        var frame = proposed
        frame.x = snap(frame.x, to: startCandidates(length: frame.width, page: pageWidth,
                                                    others: others.map { (start: $0.x, end: $0.maxX) }))
        frame.y = snap(frame.y, to: startCandidates(length: frame.height, page: pageHeight,
                                                    others: others.map { (start: $0.y, end: $0.maxY) }))
        // Nur die Lage auf ganze Punkte runden - die Breite/Hoehe bleibt, wie
        // sie hereinkam (manche Groessen der Leistungsseite sind Halbpunkte,
        // z. B. 413,5; Runden wuerde sie ausserhalb ihrer Spanne schieben).
        frame.x = frame.x.rounded()
        frame.y = frame.y.rounded()
        return frame
    }

    /// Groesse ziehen (Griff unten rechts, Ecke oben links bleibt): die Hoehe
    /// springt auf die naechste erlaubte, die Breite bleibt in der Spanne
    /// dieser Groesse und rastet bei flexiblen Widgets am Seitenrand und an
    /// Nachbarn ein (rechte Kanten buendig oder `spacing` vor dem Nachbarn).
    public static func snapResize(_ frame: WidgetFrame, kind: WidgetKind, proposedWidth: Double,
                                  proposedHeight: Double, others: [WidgetFrame]) -> WidgetFrame {
        guard let size = kind.sizes.min(by: { abs($0.height - proposedHeight) < abs($1.height - proposedHeight) })
        else { return frame }
        var width = min(max(proposedWidth, size.minWidth), size.maxWidth)
        if size.isFlexible {
            var candidates = [pageWidth - frame.x]
            for other in others {
                candidates += [other.x - spacing - frame.x, other.maxX - frame.x]
            }
            width = snap(width, to: candidates.filter { $0 >= size.minWidth && $0 <= size.maxWidth })
            // Erst runden, dann wieder in die Spanne der Groesse zwingen -
            // ein Halbpunkt-Hoechstmass (z. B. 413,5) bleibt so unangetastet,
            // statt durchs Runden ungueltig zu werden.
            width = min(max(width.rounded(), size.minWidth), size.maxWidth)
        }
        // Eine feste Breite (minWidth == maxWidth) ist bereits der genaue
        // Katalogwert - nie runden, sonst wird z. B. 169,5 ungueltig.
        return WidgetFrame(x: frame.x.rounded(), y: frame.y.rounded(), width: width, height: size.height)
    }

    /// Neues Widget aus Nexus: kleinste Groesse, mittig unter dem Zeiger
    /// (`x`, `y` in Referenzpunkten), dann eingerastet wie beim Ziehen.
    public static func dropFrame(kind: WidgetKind, x: Double, y: Double, others: [WidgetFrame]) -> WidgetFrame {
        let size = kind.smallestSize
        let proposed = WidgetFrame(x: x - size.minWidth / 2, y: y - size.height / 2,
                                   width: size.minWidth, height: size.height)
        return snapMove(proposed, others: others)
    }

    /// Moegliche Anfaenge auf einer Achse: beide Seitenraender, dieselbe
    /// Flucht wie ein anderes Widget (Anfang an Anfang, Ende an Ende) und
    /// genau `spacing` davor oder dahinter.
    static func startCandidates(length: Double, page: Double, others: [(start: Double, end: Double)]) -> [Double] {
        var result = [0, page - length]
        for other in others {
            result += [other.start, other.end - length, other.end + spacing, other.start - spacing - length]
        }
        return result
    }

    static func snap(_ value: Double, to candidates: [Double]) -> Double {
        guard let best = candidates.min(by: { abs($0 - value) < abs($1 - value) }),
              abs(best - value) < snapDistance else { return value }
        return best
    }
}
