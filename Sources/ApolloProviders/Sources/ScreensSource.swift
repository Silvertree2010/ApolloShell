import Foundation

public struct ScreenState: Equatable, Sendable {
    public var name: String
    public var frame: CGRect
    public var visibleFrame: CGRect
    public var scale: Double
    public var primary: Bool
    public var notch: Bool
    public var menubarHeight: Double
    public var fullscreen: Bool

    public init(name: String, frame: CGRect, visibleFrame: CGRect, scale: Double, primary: Bool, notch: Bool, menubarHeight: Double, fullscreen: Bool) {
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.scale = scale
        self.primary = primary
        self.notch = notch
        self.menubarHeight = menubarHeight
        self.fullscreen = fullscreen
    }
}

@MainActor
public protocol ScreensSource: AnyObject {
    func screens() -> [ScreenState]
    func observeChanges(_ handler: @escaping @MainActor () -> Void)
    func stopObserving()
}
