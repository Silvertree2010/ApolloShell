import ApolloShellCore
import Testing

@Suite("Klick im Dock der Leiste")
struct DockClickTests {
    @Test("Modifikatoren wie im Apple-Dock")
    func modifiers() {
        #expect(DockClickAction.action(command: false, option: false) == .open)
        #expect(DockClickAction.action(command: false, option: true) == .openHidingPrevious)
        #expect(DockClickAction.action(command: true, option: true) == .openHidingOthers)
        #expect(DockClickAction.action(command: true, option: false) == .reveal)
    }
}
