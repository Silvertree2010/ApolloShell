import Foundation
import Testing
@testable import ApolloShellCore

// The protocol behind the preset menus (BarPreset, UtilitiesPreset,
// DashboardPreset) and the confirmation that loads a preset or the
// default. A small test building block covers the generic mechanism, so
// the three real enums only need their own `default` preset.

private enum FruitBasket: String, CaseIterable, Identifiable, Sendable {
    case empty, full

    var id: Self { self }
}

extension FruitBasket: LayoutPreset {
    var title: String { rawValue }
    var summary: String { "Preset \(rawValue)" }
    var layout: Int { self == .empty ? 0 : 3 }
    static var `default`: FruitBasket { .empty }
}

@Suite("LayoutPreset")
struct LayoutPresetTests {
    @Test("a preset replaces with its own layer")
    func presetReplacement() {
        let replacement = LayoutPresetReplacement<FruitBasket>.preset(.full)
        #expect(replacement.layout == 3)
        #expect(replacement.confirmLabel == String(localized: "Load"))
    }

    @Test("resetting replaces with the default")
    func resetReplacement() {
        let replacement = LayoutPresetReplacement<FruitBasket>.reset
        #expect(replacement.layout == FruitBasket.default.layout)
        #expect(replacement.layout == 0)
        #expect(replacement.confirmLabel == String(localized: "Reset"))
    }

    @Test("BarPreset: Caelestia is the default")
    func barDefault() {
        #expect(BarPreset.default == .caelestia)
        #expect(BarPreset.default.layout == BarLayout.migrated())
    }

    @Test("UtilitiesPreset: Standard is the default")
    func utilitiesDefault() {
        #expect(UtilitiesPreset.default == .standard)
        #expect(UtilitiesPreset.default.layout == UtilitiesLayout())
    }

    @Test("DashboardPreset: Caelestia is the default")
    func dashboardDefault() {
        #expect(DashboardPreset.default == .caelestia)
        #expect(DashboardPreset.default.layout == DashboardLayout())
    }
}
