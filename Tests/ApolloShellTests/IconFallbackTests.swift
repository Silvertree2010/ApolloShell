import Testing
import AppKit
import ApolloShellCore
@testable import ApolloShell

@MainActor
@Suite("Theme-Icon-Fallbacks")
struct IconFallbackTests {
    @Test("jeder Standard-Fallback ist ein SF Symbol oder ein eingebautes Icon")
    func catalogResolves() {
        for icon in ThemeIconCatalog.standard.icons where !icon.fallback.isEmpty {
            let ok = BuiltinIcon.names.contains(icon.fallback) || NSImage(systemSymbolName: icon.fallback, accessibilityDescription: nil) != nil
            #expect(ok, "\(icon.id): \(icon.fallback)")
        }
    }

    @Test("icon status-bluetooth ohne fallback= zeichnet die Rune statt eines Platzhalters")
    func bluetoothWithoutFallback() {
        let fb = IconElement.fallback("status-bluetooth", nil)
        #expect(IconElement.builtinTarget("status-bluetooth", fallback: fb) == "builtin:bluetooth-rune")
        #expect(IconElement.symbol("status-bluetooth-off", fallback: IconElement.fallback("status-bluetooth-off", nil)) != "questionmark.square.dashed")
        #expect(IconElement.fallback("status-wifi", "x") == "x")
    }
}
