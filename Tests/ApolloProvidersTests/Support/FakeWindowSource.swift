@testable import ApolloProviders

@MainActor
final class FakeWindowSource: WindowSource {
    var state: FrontWindowState? = FrontWindowState(bundleID: "com.apple.Safari", appName: "Safari", appPath: "/Applications/Safari.app", title: "Apple", fullscreen: false)
    var observing = false
    var starts = 0
    private var handler: (@MainActor (FrontWindowState?) -> Void)?

    func start(_ handler: @escaping @MainActor (FrontWindowState?) -> Void) {
        observing = true
        starts += 1
        self.handler = handler
        handler(state)
    }

    func stop() {
        observing = false
        handler = nil
    }

    func change(_ state: FrontWindowState?) {
        self.state = state
        handler?(state)
    }
}
