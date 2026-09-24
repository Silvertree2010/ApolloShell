import Foundation

public enum AppleDockPrefs {
    public static let finder = "com.apple.finder"
    public static let forkLift = "com.binarynights.ForkLift"

    public static func pinnedBundleIDs(_ persistentApps: [Any], fileManager: String = finder) -> [String] {
        let ids = persistentApps.compactMap { item -> String? in
            guard let tile = (item as? [String: Any])?["tile-data"] as? [String: Any] else { return nil }
            return tile["bundle-identifier"] as? String
        }
        return [fileManager] + ids.filter { $0 != finder && $0 != fileManager }
    }

    public enum Position: Equatable, Sendable {
        case start
        case end
        case before(String)
        case after(String)
    }

    public static func bundleID(ofTile tile: Any) -> String? {
        ((tile as? [String: Any])?["tile-data"] as? [String: Any])?["bundle-identifier"] as? String
    }

    public static func tile(bundleID: String, url: URL, label: String, guid: Int) -> [String: Any] {
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
