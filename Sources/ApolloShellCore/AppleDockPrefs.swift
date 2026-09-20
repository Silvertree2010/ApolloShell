import Foundation

/// The pinned apps out of Apple's Dock setting (com.apple.dock,
/// "persistent-apps") - so that the Dock of the bar shows exactly what Apple's
/// Dock shows, even while that one is hidden.
public enum AppleDockPrefs {
    /// Always stands at the very top in Apple's Dock, but is missing from persistent-apps.
    public static let finder = "com.apple.finder"
    /// A file manager that can replace the Finder: it stands in the Dock of the
    /// bar at the Finder's place, and the Finder itself disappears from there
    /// entirely - two file manager symbols above each other would be double.
    public static let forkLift = "com.binarynights.ForkLift"

    /// `persistentApps`: the value of "persistent-apps", a list of tiles
    /// `{"tile-data": {"bundle-identifier": ...}}`. Tiles without a bundle ID
    /// (loose programs) fall away. `fileManager` stands at the very top, where
    /// Apple shows the Finder.
    public static func pinnedBundleIDs(_ persistentApps: [Any], fileManager: String = finder) -> [String] {
        let ids = persistentApps.compactMap { item -> String? in
            guard let tile = (item as? [String: Any])?["tile-data"] as? [String: Any] else { return nil }
            return tile["bundle-identifier"] as? String
        }
        return [fileManager] + ids.filter { $0 != finder && $0 != fileManager }
    }

    // MARK: - Changing (pinning, removing, moving out of the bar)

    /// Where an app should go in the list.
    public enum Position: Equatable, Sendable {
        case start
        case end
        case before(String)
        case after(String)
    }

    public static func bundleID(ofTile tile: Any) -> String? {
        ((tile as? [String: Any])?["tile-data"] as? [String: Any])?["bundle-identifier"] as? String
    }

    /// A new tile in the format Apple's Dock writes itself (measured against
    /// existing entries: tile-type, tile-data with the bundle ID, the name,
    /// file-type 41 = app, the URL as a string of type 15, plus a GUID).
    public static func tile(bundleID: String, url: URL, label: String, guid: Int) -> [String: Any] {
        // Apps are folders, and Apple's Dock writes them with a "/" at the end.
        // Whether `url` has that already would otherwise depend on whether the
        // app lies on the disk right now.
        let appURL = URL(fileURLWithPath: url.path, isDirectory: true)
        return [
            "GUID": guid,
            "tile-type": "file-tile",
            "tile-data": [
                "bundle-identifier": bundleID,
                "file-label": label,
                "file-type": 41,
                "file-data": ["_CFURLString": appURL.absoluteString, "_CFURLStringType": 15],
            ] as [String: Any],
        ]
    }

    public static func removing(_ id: String, from tiles: [Any]) -> [Any] {
        tiles.filter { bundleID(ofTile: $0) != id }
    }

    /// Puts `id` at `position`. When it stands in the list already, its tile is
    /// moved (so it is kept unchanged), otherwise `newTile` is added. An
    /// unknown target: at the end.
    public static func placing(_ id: String, at position: Position, in tiles: [Any],
                               newTile: () -> [String: Any]) -> [Any] {
        let existing = tiles.first { bundleID(ofTile: $0) == id }
        var rest = removing(id, from: tiles)
        let index: Int
        switch position {
        case .start:
            index = 0
        case .end:
            index = rest.count
        case .before(let target):
            index = rest.firstIndex { bundleID(ofTile: $0) == target } ?? rest.count
        case .after(let target):
            index = rest.firstIndex { bundleID(ofTile: $0) == target }.map { $0 + 1 } ?? rest.count
        }
        rest.insert(existing ?? newTile(), at: index)
        return rest
    }
}
