import Foundation

/// A launchable app, as it appears in the list.
public struct AppEntry: Hashable, Sendable, Identifiable {
    public var id: URL { url }

    /// Key for the usage statistics: bundle ID, otherwise the path.
    public var usageKey: String { bundleID ?? url.path }

    public let name: String
    public let url: URL
    public let bundleID: String?

    public init(name: String, url: URL, bundleID: String?) {
        self.name = name
        self.url = url
        self.bundleID = bundleID
    }
}
