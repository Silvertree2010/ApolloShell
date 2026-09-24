@testable import ApolloProviders

@MainActor
final class FakeSpacesSource: SpacesSource {
    var available = true
    var accessibilityTrusted = true
    var mainScreen: String? = "MAIN"
    var displays = [
        DisplaySpaces(screen: "MAIN", spaces: [SpaceEntry(id: 1), SpaceEntry(id: 2), SpaceEntry(id: 9, fullscreen: true), SpaceEntry(id: 3)], activeID: 2),
        DisplaySpaces(screen: "SIDE", spaces: [SpaceEntry(id: 20)], activeID: 20),
    ]
    var reads = 0
    var steps: [Bool] = []
    var missionControlCount = 0
    var observing = false
    private var handler: (@MainActor () -> Void)?

    func read() -> [DisplaySpaces] {
        reads += 1
        return available ? displays : []
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        observing = true
        self.handler = handler
    }

    func stopObserving() {
        observing = false
        handler = nil
    }

    func activate(_ id: UInt64) {
        displays[0].activeID = id
        handler?()
    }

    func step(right: Bool) {
        steps.append(right)
    }

    func missionControl() {
        missionControlCount += 1
    }
}
