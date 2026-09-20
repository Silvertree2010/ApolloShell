import AppKit
import ApolloShellCore
import SwiftUI

extension Color {
    /// Text and symbol color on `Color.accentColor`: white as in macOS,
    /// unless the accent is so light that white disappears on it (yellow),
    /// see `AccentContrast`.
    ///
    /// Re-read on every draw; if the accent is changed in Settings, it's
    /// correct by the next opening at the latest.
    static var onAccent: Color {
        guard let rgb = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return .white }
        let dark = AccentContrast.prefersDarkForeground(
            red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent
        )
        return dark ? Color.black.opacity(0.85) : .white
    }
}
