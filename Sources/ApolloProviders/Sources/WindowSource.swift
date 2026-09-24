public struct FrontWindowState: Equatable, Sendable {
    public var bundleID: String?
    public var appName: String?
    public var appPath: String?
    public var title: String?
    public var fullscreen: Bool

    public init(bundleID: String?, appName: String?, appPath: String?, title: String?, fullscreen: Bool) {
        self.bundleID = bundleID
        self.appName = appName
        self.appPath = appPath
        self.title = title
        self.fullscreen = fullscreen
    }
}

@MainActor
public protocol WindowSource: AnyObject {
    func start(_ handler: @escaping @MainActor (FrontWindowState?) -> Void)
    func stop()
}
