import Foundation
import Testing
import ApolloConfig
import ApolloRuntime
@testable import ApolloProviders

@MainActor
@Suite("Provider screens")
struct ScreensProviderTests {
    func make() -> (ProviderHarness, FakeScreensSource) {
        let harness = ProviderHarness()
        let source = FakeScreensSource()
        harness.register(ScreensProvider(source: source, clock: harness.clock))
        return (harness, source)
    }

    @Test("Liefert jedes Registry-Feld, Bildschirm-Record vollständig, NaN wird null")
    func deliversAllFields() throws {
        let (harness, _) = make()
        harness.demand("screens")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("screens")).isEmpty)
        guard case .list(let list) = harness.value("screens", "list") else { Issue.record("keine Liste"); return }
        #expect(list.count == 2)
        guard case .record(let first) = list[0], case .record(let second) = list[1] else { Issue.record("kein Record"); return }
        #expect(first.keys == ["id", "name", "main", "index", "x", "y", "width", "height", "visible-x", "visible-y", "visible-width", "visible-height", "scale", "notch", "menubar-height", "fullscreen", "notch-left", "notch-right"])
        #expect(first["id"] == .string("Built-in Retina Display 1512x982"))
        #expect(first["index"] == .number(1))
        #expect(first["notch"] == .bool(true))
        #expect(first["visible-height"] == .number(944))
        #expect(second["index"] == .number(2))
        #expect(second["scale"] == .null)
        #expect(harness.value("screens", "main.name") == .string("Built-in Retina Display"))
    }

    @Test("Ereignis mit neuer Liste nur bei Änderung der Bildschirme, Beobachter nur solange gefragt")
    func eventsAndDemand() {
        let (harness, source) = make()
        #expect(!source.observing)
        let token = harness.demand("screens", "list")
        #expect(source.observing)
        #expect(harness.events.isEmpty)
        source.change(source.list)
        #expect(harness.events.isEmpty)
        source.change([FakeScreensSource.builtin])
        #expect(harness.eventNames() == ["screens.changed"])
        guard case .list(let screens) = harness.events[0].fields["screens"] ?? .null else { Issue.record("keine Liste"); return }
        #expect(screens.count == 1)
        var fullscreen = FakeScreensSource.builtin
        fullscreen.fullscreen = true
        source.change([fullscreen])
        harness.flush()
        #expect(harness.eventNames() == ["screens.changed"])
        #expect(harness.value("screens", "main.fullscreen") == .bool(true))
        harness.release(token)
        #expect(!source.observing)
    }
}
