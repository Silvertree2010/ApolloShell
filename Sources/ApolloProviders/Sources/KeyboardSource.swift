public struct KeyboardInputSource: Equatable, Sendable {
    public var id: String
    public var name: String
    public var short: String

    public init(id: String, name: String, short: String) {
        self.id = id
        self.name = name
        self.short = short
    }
}

@MainActor
public protocol KeyboardSource: AnyObject {
    var current: KeyboardInputSource? { get }
    var sources: [KeyboardInputSource] { get }
    var capsLock: Bool { get }
    func observeChanges(_ handler: @escaping @MainActor () -> Void)
    func stopObserving()
    func select(_ id: String) -> Bool
}
