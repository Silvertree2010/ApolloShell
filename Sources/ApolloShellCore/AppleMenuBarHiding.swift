import Foundation

public enum AppleMenuBarHiding {
    public static let key = "_HIHideMenuBar"
    public static let notification = "AppleInterfaceMenuBarHidingChangedNotification"
}

public struct AppleMenuBarOriginal: Codable, Equatable, Sendable {
    public var hidden: Bool?

    public init(hidden: Bool? = nil) {
        self.hidden = hidden
    }

    public static func load(from data: Data?) -> AppleMenuBarOriginal? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(AppleMenuBarOriginal.self, from: data)
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}
