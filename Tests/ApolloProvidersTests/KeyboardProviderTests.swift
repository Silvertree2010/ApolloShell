import Testing
import ApolloConfig
import ApolloRuntime
@testable import ApolloProviders

@MainActor
@Suite("Provider keyboard")
struct KeyboardProviderTests {
    func make() -> (ProviderHarness, FakeKeyboardSource) {
        let harness = ProviderHarness()
        let source = FakeKeyboardSource()
        harness.register(KeyboardProvider(source: source, clock: harness.clock))
        return (harness, source)
    }

    @Test("Liefert jedes Registry-Feld")
    func deliversAllFields() {
        let (harness, _) = make()
        harness.demand("keyboard")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("keyboard")).isEmpty)
        #expect(harness.value("keyboard", "source.short") == .string("DE"))
        #expect(harness.value("keyboard", "caps-lock") == .bool(false))
    }

    @Test("Aktionen wechseln die Quelle, Ereignis nur bei Wechsel, Start und Stopp nach Nachfrage")
    func actionsEventsDemand() async throws {
        let (harness, source) = make()
        #expect(!source.observing)
        let token = harness.demand("keyboard", "source")
        #expect(source.observing)
        _ = try await harness.perform("keyboard", "keyboard.next-source")
        #expect(harness.value("keyboard", "source.id") == .string("com.apple.keylayout.US"))
        _ = try await harness.perform("keyboard", "keyboard.next-source")
        #expect(source.selections == ["com.apple.keylayout.US", "com.apple.keylayout.SwissGerman"])
        source.toggleCapsLock()
        #expect(harness.eventNames() == ["keyboard.source-changed", "keyboard.source-changed"])
        await #expect(throws: ProviderActionError.self) {
            try await harness.perform("keyboard", "keyboard.select", [.string("nope")])
        }
        harness.release(token)
        #expect(!source.observing)
    }
}
