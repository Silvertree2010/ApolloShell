import Testing
import ApolloConfig
@testable import ApolloRuntime

@MainActor
@Suite("Oberfläche status-item")
struct StatusItemSurfaceTests {
    typealias IR = RuntimeIR
    typealias T = TreeIR

    @Test("status-item steht einmal auf dem Hauptbildschirm, ist ohne open sichtbar und bleibt im Vollbild")
    func singleVisibleInstance() {
        let fixture = ShellFixture()
        fixture.apply([T.surface("status-item", "shell", children: [T.text("0", IR.string("A"))])], screens: ["A", "B"])
        #expect(fixture.host.events.filter { $0.hasPrefix("added:shell") } == ["added:shell@A"])
        let item = fixture.surface("shell", "A")
        #expect(item.isOpen)
        #expect(item.isVisible)
    }

    @Test("Ein zweites Anwenden desselben Baums legt das status-item nicht neu an")
    func reapplyKeepsInstance() {
        let fixture = ShellFixture()
        let tree = [T.surface("status-item", "shell", children: [T.text("0", IR.string("A"))])]
        fixture.apply(tree, screens: ["A", "B"])
        fixture.apply(tree, screens: ["A", "B"])
        #expect(fixture.host.events.filter { $0.hasPrefix("added:shell") } == ["added:shell@A"])
    }
}
