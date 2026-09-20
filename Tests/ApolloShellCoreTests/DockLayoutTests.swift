import ApolloShellCore
import Testing

@Suite("The Dock in the bar")
struct DockLayoutTests {
    private let all: (String) -> Bool = { _ in true }

    @Test("the pinned ones in their order first, then the other running ones")
    func order() {
        let slots = DockLayout.slots(pinned: ["kitty", "vivaldi", "spotify"], running: ["finder", "vivaldi", "mail"], isAvailable: all)
        #expect(slots.map(\.bundleID) == ["kitty", "vivaldi", "spotify", "finder", "mail"])
        #expect(slots.map(\.pinned) == [true, true, true, false, false])
        #expect(slots.map(\.running) == [false, true, false, true, true])
    }

    @Test("every app only once")
    func unique() {
        let slots = DockLayout.slots(pinned: ["kitty", "kitty"], running: ["mail", "mail", "kitty"], isAvailable: all)
        #expect(slots.map(\.bundleID) == ["kitty", "mail"])
    }

    @Test("pinned but no longer installed: it falls away")
    func missingPinned() {
        let slots = DockLayout.slots(pinned: ["weg", "kitty"], running: [], isAvailable: { $0 != "weg" })
        #expect(slots.map(\.bundleID) == ["kitty"])
    }

    @Test("a hidden app never appears, even when it runs or is pinned")
    func hidden() {
        let slots = DockLayout.slots(pinned: ["forklift", "finder"], running: ["finder", "mail"],
                                     hidden: ["finder"], isAvailable: all)
        #expect(slots.map(\.bundleID) == ["forklift", "mail"])
    }

    @Test("the file manager always has a dot, even when it does not run")
    func alwaysRunning() {
        let slots = DockLayout.slots(pinned: ["forklift", "kitty"], running: [], alwaysRunning: ["forklift"],
                                     isAvailable: all)
        #expect(slots.map(\.running) == [true, false])
    }

    @Test("nothing pinned: only the running ones")
    func onlyRunning() {
        let slots = DockLayout.slots(pinned: [], running: ["finder"], isAvailable: all)
        #expect(slots == [DockSlot(bundleID: "finder", pinned: false, running: true)])
    }
}
