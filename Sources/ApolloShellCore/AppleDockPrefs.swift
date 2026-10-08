import Foundation

/// Angeheftete Apps aus Apples Dock-Einstellung (com.apple.dock,
/// "persistent-apps") - damit das Dock der Leiste genau zeigt, was Apples
/// Dock zeigt, auch wenn der selbst ausgeblendet ist.
public enum AppleDockPrefs {
    /// Steht in Apples Dock immer zuoberst, fehlt aber in persistent-apps.
    public static let finder = "com.apple.finder"
    /// Dateimanager, der Finder ersetzen kann: steht im Dock der Leiste an
    /// Finders Platz, Finder selbst verschwindet dort ganz - zwei
    /// Dateimanager-Symbole uebereinander waeren doppelt.
    public static let forkLift = "com.binarynights.ForkLift"

    /// `persistentApps`: der Wert von "persistent-apps", eine Liste von
    /// Kacheln `{"tile-data": {"bundle-identifier": ...}}`. Kacheln ohne
    /// Bundle-ID (lose Programme) fallen weg. `fileManager` steht zuoberst,
    /// wo Apple den Finder zeigt.
    public static func pinnedBundleIDs(_ persistentApps: [Any], fileManager: String = finder) -> [String] {
        let ids = persistentApps.compactMap { item -> String? in
            guard let tile = (item as? [String: Any])?["tile-data"] as? [String: Any] else { return nil }
            return tile["bundle-identifier"] as? String
        }
        return [fileManager] + ids.filter { $0 != finder && $0 != fileManager }
    }

    // MARK: - Aendern (Anheften, Entfernen, Verschieben aus der Leiste)

    /// Wohin eine App in der Liste soll.
    public enum Position: Equatable, Sendable {
        case start
        case end
        case before(String)
        case after(String)
    }

    public static func bundleID(ofTile tile: Any) -> String? {
        ((tile as? [String: Any])?["tile-data"] as? [String: Any])?["bundle-identifier"] as? String
    }

    /// Eine neue Kachel im Format, das Apples Dock selbst schreibt
    /// (gemessen an vorhandenen Eintraegen: tile-type, tile-data mit Bundle-ID,
    /// Name, file-type 41 = App, URL als Zeichenkette Typ 15, dazu eine GUID).
    public static func tile(bundleID: String, url: URL, label: String, guid: Int) -> [String: Any] {
        // Apps sind Ordner, Apples Dock schreibt sie mit "/" am Ende. Ob
        // `url` das schon hat, haengt sonst davon ab, ob die App gerade auf
        // der Platte liegt.
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

    /// Setzt `id` an `position`. Steht sie schon in der Liste, wird ihre
    /// Kachel verschoben (bleibt also unveraendert erhalten), sonst kommt
    /// `newTile` hinzu. Unbekanntes Ziel: ans Ende.
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

extension AppleDockPrefs {
    public static func otherURLs(_ tiles: [Any]) -> [URL] {
        tiles.compactMap { item in
            guard let d = (item as? [String: Any])?["tile-data"] as? [String: Any],
                  let f = d["file-data"] as? [String: Any], let s = f["_CFURLString"] as? String else { return nil }
            if let u = URL(string: s), u.isFileURL { return u }
            return s.hasPrefix("/") ? URL(fileURLWithPath: s) : nil
        }
    }

    public static func otherTile(url: URL, label: String, folder: Bool, guid: Int) -> [String: Any] {
        let u = URL(fileURLWithPath: url.path, isDirectory: folder)
        var data: [String: Any] = [
            "file-label": label,
            "file-type": folder ? 2 : 32,
            "file-data": ["_CFURLString": u.absoluteString, "_CFURLStringType": 15],
        ]
        if folder {
            data["arrangement"] = 2
            data["displayas"] = 0
            data["showas"] = 0
            data["preferreditemsize"] = -1
        }
        return ["GUID": guid, "tile-type": folder ? "directory-tile" : "file-tile", "tile-data": data]
    }

    public static func removingOther(_ url: URL, from tiles: [Any]) -> [Any] {
        let p = url.standardizedFileURL.path
        return tiles.filter { item in
            otherURLs([item]).first.map { $0.standardizedFileURL.path != p } ?? true
        }
    }
}
