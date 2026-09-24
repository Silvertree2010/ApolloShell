import Foundation

/// Findet alle Apps in den ueblichen Ordnern.
///
/// Sucht zwei Ebenen tief, weil manche Hersteller ihre App in einen
/// eigenen Ordner legen (z.B. "/Applications/Adobe Illustrator 2026/...").
/// In ein .app-Bundle selbst wird nie hineingesucht: darin liegen oft
/// Hilfs-Apps, die man nicht direkt starten soll.
public struct AppCatalog: Sendable {
    public static let defaultRoots: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications"),
    ]

    public var roots: [URL]
    public var maxDepth: Int

    public init(roots: [URL] = AppCatalog.defaultRoots, maxDepth: Int = 2) {
        self.roots = roots
        self.maxDepth = maxDepth
    }

    /// Alphabetisch sortiert, jede App nur einmal (nach Bundle-ID).
    public func scan() -> [AppEntry] {
        var found: [AppEntry] = []
        for root in roots {
            collect(in: root, depth: 1, into: &found)
        }
        var seen = Set<String>()
        let unique = found.filter { entry in
            guard let id = entry.bundleID else { return true }
            return seen.insert(id).inserted
        }
        return unique.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func collect(in directory: URL, depth: Int, into found: inout [AppEntry]) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in items {
            if item.pathExtension == "app" {
                found.append(Self.entry(for: item))
            } else if depth < maxDepth,
                      (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                collect(in: item, depth: depth + 1, into: &found)
            }
        }
    }

    private static func entry(for app: URL) -> AppEntry {
        var name = FileManager.default.displayName(atPath: app.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return AppEntry(name: name, url: app, bundleID: bundleID(of: app))
    }

    private static func bundleID(of app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }
}
