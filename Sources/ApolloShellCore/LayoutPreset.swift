import Foundation

// Was `BarPreset`, `UtilitiesPreset` und `DashboardPreset` gemeinsam haben:
// eine feste Liste fertiger Ebenen, jede mit Titel, Zusammenfassung und der
// Ebene, die sie erzeugt - dazu eine Vorgabe, auf die "Zuruecksetzen" fuehrt.
// Nexus baut darauf die Rueckfrage vors Ersetzen (siehe NexusPresetControls
// im App-Ziel); die drei Vorlagen-Enums selbst bleiben, wo sie stehen (bei
// ihrer Ebene), nur ihre Konformitaet steht hier daneben.

/// Eine Vorlage fuer eine Ebene (Leiste, Panel oder Dashboard): Titel und
/// Zusammenfassung fuer Menue und Rueckfrage, `layout` die fertige Ebene.
public protocol LayoutPreset: CaseIterable, Identifiable, Sendable where AllCases: RandomAccessCollection {
    associatedtype Layout: Equatable, Sendable

    var title: String { get }
    var summary: String { get }
    var layout: Layout { get }

    /// Worauf "Zuruecksetzen" fuehrt - bei allen dreien die erste, "Caelestia"
    /// bzw. "Standard" genannte Vorlage.
    static var `default`: Self { get }
}

/// Was eine Rueckfrage in Nexus am Ende ersetzt: eine gewaehlte Vorlage oder
/// die Vorgabe. Die Texte der Rueckfrage bleiben bei den Editoren, weil sich
/// ihre Formulierungen unterscheiden (Leiste/Panel/Dashboard) - hier nur, was
/// beiden Faellen gemeinsam ist.
public enum LayoutPresetReplacement<P: LayoutPreset> {
    case preset(P)
    case reset

    public var layout: P.Layout {
        switch self {
        case .preset(let preset): preset.layout
        case .reset: P.default.layout
        }
    }

    /// Beschriftung des Bestaetigen-Knopfs - bei allen dreien gleich.
    public var confirmLabel: String {
        switch self {
        case .preset: String(localized: "Laden")
        case .reset: String(localized: "Zurücksetzen")
        }
    }
}
