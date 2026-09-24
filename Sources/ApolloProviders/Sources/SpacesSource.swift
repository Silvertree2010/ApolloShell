import Foundation

public struct SpaceEntry: Equatable, Sendable {
    public var id: UInt64
    public var fullscreen: Bool

    public init(id: UInt64, fullscreen: Bool = false) {
        self.id = id
        self.fullscreen = fullscreen
    }
}

public struct DisplaySpaces: Equatable, Sendable {
    public var screen: String
    public var spaces: [SpaceEntry]
    public var activeID: UInt64?

    public init(screen: String, spaces: [SpaceEntry], activeID: UInt64?) {
        self.screen = screen
        self.spaces = spaces
        self.activeID = activeID
    }
}

@MainActor
public protocol SpacesSource: AnyObject {
    var available: Bool { get }
    var accessibilityTrusted: Bool { get }
    var mainScreen: String? { get }
    func read() -> [DisplaySpaces]
    func observeChanges(_ handler: @escaping @MainActor () -> Void)
    func stopObserving()
    func step(right: Bool)
    func missionControl()
}
