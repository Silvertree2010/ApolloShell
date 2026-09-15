import Foundation

/// Eine startbare App, so wie sie in der Liste erscheint.
public struct AppEntry: Hashable, Sendable, Identifiable {
    public var id: URL { url }

    /// Schluessel fuer die Nutzungsstatistik: Bundle-ID, sonst der Pfad.
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
