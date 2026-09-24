import Testing
import ApolloConfig
import ApolloRuntime
@testable import ApolloProviders

@MainActor
@Suite("Provider window")
struct WindowProviderTests {
    func make(appRecord: (@MainActor (String) -> Value?)? = nil) -> (ProviderHarness, FakeWindowSource) {
        let harness = ProviderHarness()
        let source = FakeWindowSource()
        let provider = WindowProvider(source: source, clock: harness.clock)
        provider.appRecord = appRecord
        harness.register(provider)
        return (harness, source)
    }

    @Test("Liefert jedes Registry-Feld mit App-Record")
    func deliversAllFields() {
        let (harness, _) = make()
        harness.demand("window")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("window")).isEmpty)
        #expect(harness.value("window", "app.bundle-id") == .string("com.apple.Safari"))
        #expect(harness.value("window", "app.name") == .string("Safari"))
        #expect(harness.value("window", "app.icon") == .image(ImageRef(source: "app-icon", id: "com.apple.Safari")))
        #expect(harness.value("window", "title") == .string("Apple"))
        #expect(harness.value("window", "fullscreen") == .bool(false))
    }

    @Test("App-Record kommt vom apps-Provider, wenn angebunden")
    func usesAppRecordResolver() {
        let (harness, _) = make(appRecord: { id in .record(Record([("bundle-id", .string(id)), ("usage", .number(3))])) })
        harness.demand("window", "app")
        #expect(harness.value("window", "app.usage") == .number(3))
    }

    @Test("Push-Änderungen, ohne Fenster null, Beobachter nur solange gefragt")
    func pushAndDemand() {
        let (harness, source) = make()
        #expect(!source.observing)
        let token = harness.demand("window", "title")
        #expect(source.observing)
        source.change(FrontWindowState(bundleID: "com.apple.Terminal", appName: "Terminal", appPath: nil, title: nil, fullscreen: true))
        harness.flush()
        #expect(harness.value("window", "title") == .null)
        #expect(harness.value("window", "fullscreen") == .bool(true))
        #expect(harness.value("window", "app.path") == .null)
        source.change(nil)
        harness.flush()
        #expect(harness.value("window", "app") == .null)
        #expect(harness.value("window", "fullscreen") == .bool(false))
        harness.release(token)
        #expect(!source.observing)
    }
}
