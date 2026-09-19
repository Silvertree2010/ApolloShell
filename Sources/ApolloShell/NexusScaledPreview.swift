import SwiftUI

/// Die verkleinerte, lebende Vorschau in Nexus > Leiste: eine leicht
/// abgesetzte Flaeche als Ersatz fuer das Glas, ein Rand, skaliert auf
/// `scale`, ohne Maus. Kopf (Ueberschrift "Vorschau") und Fusszeile
/// (Beispieldaten-Hinweis) bleiben beim Aufrufer. Dashboard und
/// Schnellaktionen hatten bis Task 7 ihre eigene Vorschau hier mit - seither
/// bearbeitet man beide im globalen Bearbeitungsmodus, am echten Panel.
///
/// `scale` wirkt auf `scaleEffect` und den Rand (`1 / scale`), `frameSize`
/// ist die fertige Aussenmasse; getrennt, falls ein Aufrufer fuer den
/// sichtbaren Massstab einen nach unten geklemmten Wert braucht, fuer den
/// Rahmen aber den ungeklemmten.
struct NexusScaledPreview<Content: View>: View {
    let scale: CGFloat
    let frameSize: CGSize
    let cornerRadius: CGFloat
    let accessibilityLabel: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(Color.primary.opacity(0.07))
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1 / scale)
            }
            .scaleEffect(scale, anchor: .top)
            .frame(width: frameSize.width, height: frameSize.height, alignment: .top)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }
}
