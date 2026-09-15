import ApolloShellCore
import Testing

@Suite("Dock in der Leiste")
struct DockLayoutTests {
    private let all: (String) -> Bool = { _ in true }

    @Test("erst angeheftete in ihrer Reihenfolge, dann die uebrigen laufenden")
    func order() {
        let slots = DockLayout.slots(pinned: ["kitty", "vivaldi", "spotify"], running: ["finder", "vivaldi", "mail"], isAvailable: all)
        #expect(slots.map(\.bundleID) == ["kitty", "vivaldi", "spotify", "finder", "mail"])
        #expect(slots.map(\.pinned) == [true, true, true, false, false])
        #expect(slots.map(\.running) == [false, true, false, true, true])
    }

    @Test("jede App nur einmal")
    func unique() {
        let slots = DockLayout.slots(pinned: ["kitty", "kitty"], running: ["mail", "mail", "kitty"], isAvailable: all)
        #expect(slots.map(\.bundleID) == ["kitty", "mail"])
    }

    @Test("angeheftet, aber nicht mehr installiert: faellt weg")
    func missingPinned() {
        let slots = DockLayout.slots(pinned: ["weg", "kitty"], running: [], isAvailable: { $0 != "weg" })
        #expect(slots.map(\.bundleID) == ["kitty"])
    }

    @Test("versteckte App erscheint nie, auch wenn sie laeuft oder angeheftet ist")
    func hidden() {
        let slots = DockLayout.slots(pinned: ["forklift", "finder"], running: ["finder", "mail"],
                                     hidden: ["finder"], isAvailable: all)
        #expect(slots.map(\.bundleID) == ["forklift", "mail"])
    }

    @Test("Dateimanager hat immer einen Punkt, auch wenn er nicht laeuft")
    func alwaysRunning() {
        let slots = DockLayout.slots(pinned: ["forklift", "kitty"], running: [], alwaysRunning: ["forklift"],
                                     isAvailable: all)
        #expect(slots.map(\.running) == [true, false])
    }

    @Test("nichts angeheftet: nur die laufenden")
    func onlyRunning() {
        let slots = DockLayout.slots(pinned: [], running: ["finder"], isAvailable: all)
        #expect(slots == [DockSlot(bundleID: "finder", pinned: false, running: true)])
    }
}
