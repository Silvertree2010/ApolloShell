import Foundation
import Testing
@testable import ApolloShellCore

// Das Protokoll hinter den Vorlagen-Menues (BarPreset, UtilitiesPreset,
// DashboardPreset) und der Rueckfrage, die eine Vorlage oder die Vorgabe
// laedt. Ein kleiner Test-Baustein deckt die generische Mechanik ab, die
// drei echten Enums nur noch ihre eigene `default`-Vorlage.

private enum FruitBasket: String, CaseIterable, Identifiable, Sendable {
    case empty, full

    var id: Self { self }
}

extension FruitBasket: LayoutPreset {
    var title: String { rawValue }
    var summary: String { "Vorlage \(rawValue)" }
    var layout: Int { self == .empty ? 0 : 3 }
    static var `default`: FruitBasket { .empty }
}

@Suite("LayoutPreset")
struct LayoutPresetTests {
    @Test("Vorlage ersetzt mit ihrer eigenen Ebene")
    func presetReplacement() {
        let replacement = LayoutPresetReplacement<FruitBasket>.preset(.full)
        #expect(replacement.layout == 3)
        #expect(replacement.confirmLabel == String(localized: "Load"))
    }

    @Test("Zuruecksetzen ersetzt mit der Vorgabe")
    func resetReplacement() {
        let replacement = LayoutPresetReplacement<FruitBasket>.reset
        #expect(replacement.layout == FruitBasket.default.layout)
        #expect(replacement.layout == 0)
        #expect(replacement.confirmLabel == String(localized: "Reset"))
    }

    @Test("BarPreset: Caelestia ist die Vorgabe")
    func barDefault() {
        #expect(BarPreset.default == .caelestia)
        #expect(BarPreset.default.layout == BarLayout.migrated())
    }

    @Test("UtilitiesPreset: Standard ist die Vorgabe")
    func utilitiesDefault() {
        #expect(UtilitiesPreset.default == .standard)
        #expect(UtilitiesPreset.default.layout == UtilitiesLayout())
    }

    @Test("DashboardPreset: Caelestia ist die Vorgabe")
    func dashboardDefault() {
        #expect(DashboardPreset.default == .caelestia)
        #expect(DashboardPreset.default.layout == DashboardLayout())
    }
}
