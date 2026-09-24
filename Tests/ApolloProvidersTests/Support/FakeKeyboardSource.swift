@testable import ApolloProviders

@MainActor
final class FakeKeyboardSource: KeyboardSource {
    static let german = KeyboardInputSource(id: "com.apple.keylayout.SwissGerman", name: "Swiss German", short: "DE")
    static let us = KeyboardInputSource(id: "com.apple.keylayout.US", name: "U.S.", short: "US")

    var sources = [german, us]
    var currentID = german.id
    var capsLock = false
    var observing = false
    var selections: [String] = []
    private var handler: (@MainActor () -> Void)?

    var current: KeyboardInputSource? { sources.first { $0.id == currentID } }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        observing = true
        self.handler = handler
    }

    func stopObserving() {
        observing = false
        handler = nil
    }

    func select(_ id: String) -> Bool {
        selections.append(id)
        guard sources.contains(where: { $0.id == id }) else { return false }
        currentID = id
        handler?()
        return true
    }

    func toggleCapsLock() {
        capsLock.toggle()
        handler?()
    }
}
