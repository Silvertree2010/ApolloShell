import Foundation

public struct MenuBarState: Equatable, Sendable {
    public var appName: String
    public var bundleID: String?
    public var titles: [String]
    public var trusted: Bool

    public init(appName: String, bundleID: String?, titles: [String], trusted: Bool) {
        self.appName = appName
        self.bundleID = bundleID
        self.titles = titles
        self.trusted = trusted
    }
}

@MainActor
public protocol MenuBarSource: AnyObject {
    func start(_ handler: @escaping @MainActor (MenuBarState?) -> Void)
    func stop()
    func press(_ path: [String]) async -> Bool
}

public struct StatusItemState: Equatable, Sendable {
    public var id: String
    public var app: String?
    public var name: String
    public var title: String
    public var hasImage: Bool
    public var imageVersion: Int
    public var kind: String?
    public var monochrome: Bool
    public var symbol: String?

    public init(id: String, app: String?, name: String, title: String = "", hasImage: Bool = false, imageVersion: Int = 0, kind: String? = nil, monochrome: Bool = false, symbol: String? = nil) {
        self.id = id
        self.app = app
        self.name = name
        self.title = title
        self.hasImage = hasImage
        self.imageVersion = imageVersion
        self.kind = kind
        self.monochrome = monochrome
        self.symbol = symbol
    }
}

@MainActor
public protocol StatusItemsSource: AnyObject {
    func start(_ handler: @escaping @MainActor ([StatusItemState]) -> Void)
    func stop()
    func click(_ id: String) async -> Bool
    func imageData(_ id: String) -> Data?
}
