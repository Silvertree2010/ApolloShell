import Testing
import ApolloConfig
@testable import ApolloRuntime

@MainActor
@Suite("Oberfläche status-item")
struct StatusItemSurfaceTests {
    @Test("status-item steht einmal auf dem Hauptbildschirm, ist ohne open sichtbar und bleibt im Vollbild")
    func singleVisibleInstance() {
        let fixture = ShellFixture()
        fixture.apply([T.surface("status-item", "shell", children: [T.text("0", IR.string("A"))])], screens: ["A", "B"])
        #expect(fixture.host.events.filter { $0.hasPrefix("added:shell") } == ["added:shell@A"])
        let item = fixture.surface("shell", "A")
        #expect(item.isOpen)
        #expect(item.isVisible)
    }
}
