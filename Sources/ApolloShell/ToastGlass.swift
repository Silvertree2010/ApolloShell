import SwiftUI

extension View {
    /// Liquid Glass hinter einer Kurzmeldung, auf Wunsch leicht getoent.
    ///
    /// Hier SwiftUIs `glassEffect` statt eines NSGlassEffectView wie bei den
    /// Kantenfenstern: dort ist das Glas das ganze Fenster, hier hat jede
    /// Meldung ihr eigenes, und das muss beim Auf- und Ausblenden mit
    /// Deckkraft und Groesse mitgehen. Ein eingebettetes AppKit-Glas folgt
    /// SwiftUIs Uebergaengen nicht sicher; das SwiftUI-Glas ist dasselbe
    /// Material und gehoert zum Uebergang. Ohne GlassEffectContainer, damit
    /// benachbarte Meldungen nicht ineinanderfliessen.
    ///
    /// Eigene Datei, damit die Bildprobe sie gegen einen Ersatz tauschen
    /// kann - Glas zeichnet offscreen nur weiss.
    func toastGlass(tint: Color?, cornerRadius: CGFloat) -> some View {
        glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
    }
}
