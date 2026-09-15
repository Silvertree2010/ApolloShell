import AppKit
import ApolloShellCore
import SwiftUI

extension Color {
    /// Schrift- und Symbolfarbe auf `Color.accentColor`: weiss wie bei macOS,
    /// ausser der Akzent ist so hell, dass weiss darauf verschwindet (Gelb),
    /// siehe `AccentContrast`.
    ///
    /// Bei jedem Zeichnen neu gelesen; wechselt man den Akzent in den
    /// Einstellungen, stimmt es spaetestens beim naechsten Oeffnen.
    static var onAccent: Color {
        guard let rgb = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return .white }
        let dark = AccentContrast.prefersDarkForeground(
            red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent
        )
        return dark ? Color.black.opacity(0.85) : .white
    }
}
