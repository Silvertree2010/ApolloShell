import Testing
import Foundation
import ApolloConfig
@testable import ApolloProviders

@MainActor
@Suite("wm-Ränder aus reserve")
struct WMReserveTests {
    let screens = [WMScreen(key: "main", isMain: true), WMScreen(key: "side", isMain: false)]

    @Test("Panels und reserve-Knoten addieren sich je Bildschirm")
    func sums() {
        var settings = WMSettings()
        settings.reserves = [WMSettings.Reserve(top: 24), WMSettings.Reserve(left: 10, screen: "side")]
        let panels = [PanelReserve(screen: "main", edge: .left, size: 44), PanelReserve(screen: "main", edge: .top, size: 30)]
        let insets = WMReserve.insets(panels: panels, settings: settings, screens: screens)
        #expect(insets["main"] == WMInsets(top: 54, left: 44))
        #expect(insets["side"] == WMInsets(top: 24, left: 10))
    }

    @Test("reserve-panels #false ignoriert Panels, fremder Schlüssel fällt auf main")
    func switches() {
        var settings = WMSettings()
        settings.reservePanels = false
        settings.reserves = [WMSettings.Reserve(bottom: 8, screen: "gone")]
        let insets = WMReserve.insets(panels: [PanelReserve(screen: "main", edge: .left, size: 44)], settings: settings, screens: screens)
        #expect(insets["main"] == WMInsets(bottom: 8))
        #expect(insets["side"] == .zero)
    }

    @Test("Der Provider gibt Ränder nur bei Änderung an die Engine")
    func provider() {
        let harness = ProviderHarness()
        let engine = FakeWMEngine()
        engine.screens = screens
        let provider = WMProvider(engine: engine, clock: harness.clock)
        harness.register(provider)
        provider.apply(WMSettings())
        provider.setPanelReserves([PanelReserve(screen: "main", edge: .left, size: 44)])
        #expect(engine.reserved.isEmpty)
        provider.configure(Record([("enabled", .bool(true))]))
        #expect(engine.reserved.last?["main"] == WMInsets(left: 44))
        let count = engine.reserved.count
        provider.setPanelReserves([PanelReserve(screen: "main", edge: .left, size: 44)])
        provider.screensChanged()
        #expect(engine.reserved.count == count)
        provider.setPanelReserves([PanelReserve(screen: "main", edge: .left, size: 60)])
        #expect(engine.reserved.last?["main"] == WMInsets(left: 60))
    }
}
