import Foundation
@testable import ApolloProviders

@MainActor
final class FakeScreensSource: ScreensSource {
    static let builtin = ScreenState(
        name: "Built-in Retina Display", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944), scale: 2, primary: true,
        notch: true, menubarHeight: 38, fullscreen: false
    )
    static let external = ScreenState(
        name: "LG UltraFine", frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1415), scale: .nan, primary: false,
        notch: false, menubarHeight: 25, fullscreen: false
    )

    var list = [builtin, external]
    var observing = false
    private var handler: (@MainActor () -> Void)?

    func screens() -> [ScreenState] { list }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) {
        observing = true
        self.handler = handler
    }

    func stopObserving() {
        observing = false
        handler = nil
    }

    func change(_ list: [ScreenState]) {
        self.list = list
        handler?()
    }
}
