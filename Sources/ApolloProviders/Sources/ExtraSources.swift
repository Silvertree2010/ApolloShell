import Foundation
import ApolloShellCore

public struct ClipboardContent: Equatable, Sendable {
    public var types: [String]
    public var text: String?

    public init(types: [String], text: String?) {
        self.types = types
        self.text = text
    }
}

@MainActor
public protocol ClipboardSource: AnyObject {
    var changeCount: Int { get }
    func read() -> ClipboardContent
}

public struct RecentFile: Equatable, Sendable {
    public var path: String
    public var name: String
    public var date: Date

    public init(path: String, name: String, date: Date) {
        self.path = path
        self.name = name
        self.date = date
    }
}

@MainActor
public protocol RecentFilesSource: AnyObject {
    func read(since: Date, limit: Int, _ completion: @escaping @MainActor ([RecentFile]) -> Void)
}

public struct DriveInfo: Equatable, Sendable {
    public var name: String
    public var path: String
    public var total: Double
    public var free: Double
    public var ejectable: Bool

    public init(name: String, path: String, total: Double, free: Double, ejectable: Bool) {
        self.name = name
        self.path = path
        self.total = total
        self.free = free
        self.ejectable = ejectable
    }

    public var used: Double { total > 0 ? (total - free) / total : 0 }
}

@MainActor
public protocol DrivesSource: AnyObject {
    func volumes() -> [DriveInfo]
    func observe(_ handler: @escaping @MainActor () -> Void)
    func stopObserving()
    func eject(_ path: String) -> Bool
}

@MainActor
public protocol PhotosSource: AnyObject {
    func pictures(in folder: String, _ completion: @escaping @MainActor ([String]) -> Void)
    func thumbnail(_ path: String) -> Data?
}

public enum NetworkLinkKind: String, Sendable {
    case wifi, wired, none
}

public struct NetworkLink: Equatable, Sendable {
    public var kind: NetworkLinkKind
    public var name: String?
    public var localAddress: String?

    public init(kind: NetworkLinkKind, name: String?, localAddress: String?) {
        self.kind = kind
        self.name = name
        self.localAddress = localAddress
    }
}

@MainActor
public protocol NetworkInfoSource: AnyObject {
    func link() -> NetworkLink
    func measureLatency(_ completion: @escaping @MainActor (Double?) -> Void)
    func fetchPublicAddress(_ completion: @escaping @MainActor (String?) -> Void)
}

@MainActor
public protocol DisplaySource: AnyObject {
    func brightness() -> Double?
    func setBrightness(_ value: Double) -> Bool
}

@MainActor
public protocol WallpaperSource: AnyObject {
    func appleWallpapers() -> [AppleWallpaper]
    func current() -> String?
    func set(_ path: String, screen: String?) -> Bool
    func thumbnail(_ path: String) -> Data?
}
