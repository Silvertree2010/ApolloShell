import AppKit
import ApolloShellCore
import SwiftUI

extension Color {
    static var onAccent: Color {
        guard let rgb = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return .white }
        let dark = AccentContrast.prefersDarkForeground(
            red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent
        )
        return dark ? Color.black.opacity(0.85) : .white
    }
}
