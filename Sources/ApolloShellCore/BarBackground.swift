import Foundation

/// Womit die Leiste und ihre Beule hinterlegt sind (Nexus > Leiste >
/// Hintergrund).
///
/// Warum es die Wahl ueberhaupt gibt: Liquid Glass in der Fassung `regular`
/// richtet sich nach der Helligkeit dessen, was dahinter liegt, und kippt
/// dabei auch zwischen heller und dunkler Erscheinung - ausdruecklich
/// unabhaengig davon, ob das System auf Hell oder Dunkel steht (Apple,
/// WWDC25 "Meet Liquid Glass": "constantly adapt their appearance depending
/// on what's behind them ... flip from light to dark based on the
/// background"). Die Leiste faerbt sich also um, sobald ein Fenster unter sie
/// faehrt.
///
/// Abschalten laesst sich das nicht: die ganze Schnittstelle dazu ist
/// NSGlassEffectView (contentView, cornerRadius, effectIsInteractive, style
/// mit regular/clear, tintColor) und SwiftUIs `Glass` (regular, clear,
/// identity, tint, interactive) - keinen Schalter fuer die Anpassung.
/// Toenen hilft nur begrenzt, weil auch die Toene auf die Helligkeit des
/// Hintergrunds abgebildet werden ("Selecting a color generates a range of
/// tones that are mapped to content brightness underneath").
///
/// Steuerbar ist nur, was hinter dem Glas liegt. Darauf laufen die Eintraege
/// hinaus: `material` ersetzt das Glas durch ein Systemmaterial mit fester
/// Erscheinung je Hell/Dunkel, `fixedGlass` legt eine deckende Flaeche unter
/// das Glas und nimmt dafuer die Fassung `clear`, die laut Apple gar keine
/// anpassenden Eigenschaften hat ("Clear ... does not have adaptive
/// behaviors ... it needs a dimming layer") - die deckende Flaeche ist diese
/// Schicht.
public enum BarBackground: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Systemmaterial statt Glas: eine Farbe je Erscheinungsbild, wechselt
    /// mit Hell/Dunkel wie ein gewoehnliches Fenster. Vorgabe.
    case material
    /// Liquid Glass, Fassung `regular` - passt sich dem an, was dahinter
    /// liegt.
    case glass
    /// Liquid Glass, Fassung `regular`, in Fensterfarbe getoent.
    case tintedGlass
    /// Klares Liquid Glass ueber einer deckenden Flaeche in Fensterfarbe.
    case fixedGlass

    public var id: Self { self }

    /// Ohne Einstellung: Material - der Stand vor dieser Wahl.
    public static let standard = material

    /// Nachsichtig wie der Rest von settings.json: ein unbekannter oder
    /// falsch getippter Wert ist die Vorgabe, kein Fehler.
    public init(from decoder: any Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        self = raw.flatMap(BarBackground.init(rawValue:)) ?? .standard
    }
}
