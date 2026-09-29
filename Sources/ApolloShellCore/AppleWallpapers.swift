import Foundation

public struct AppleWallpaper: Hashable, Sendable {
    public let name: String
    public let url: URL?
    public let thumbnail: URL?

    public init(name: String, url: URL?, thumbnail: URL?) {
        self.name = name
        self.url = url
        self.thumbnail = thumbnail
    }

    public var isAvailable: Bool { url != nil }

    public static let folder = URL(fileURLWithPath: "/System/Library/Desktop Pictures", isDirectory: true)

    public static var downloads: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.mobileAssetDesktop", isDirectory: true)
    }

    public static func all(folder: URL = folder, downloads: URL = downloads) -> [AppleWallpaper] {
        let manager = FileManager.default
        let thumbnails = folder.appendingPathComponent(".thumbnails", isDirectory: true)
        var result: [AppleWallpaper] = []
        let entries = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let pictures: Set<String> = ["heic", "jpg", "jpeg", "png"]
        for url in entries where url.pathExtension == "madesktop" || pictures.contains(url.pathExtension.lowercased()) {
            let name = url.deletingPathExtension().lastPathComponent
            let thumb = thumbnails.appendingPathComponent(name + ".heic")
            let isAsset = url.pathExtension == "madesktop"
            let preview = manager.fileExists(atPath: thumb.path) ? thumb : (isAsset ? nil : url)
            let downloaded = downloads.appendingPathComponent(name + ".heic")
            let picture = isAsset ? (manager.fileExists(atPath: downloaded.path) ? downloaded : nil) : url
            result.append(AppleWallpaper(name: name, url: picture, thumbnail: preview))
        }
        let solid = folder.appendingPathComponent("Solid Colors", isDirectory: true)
        for url in (try? manager.contentsOfDirectory(at: solid, includingPropertiesForKeys: nil)) ?? []
        where ["png", "jpg", "heic"].contains(url.pathExtension.lowercased()) {
            result.append(AppleWallpaper(name: url.deletingPathExtension().lastPathComponent, url: url, thumbnail: url))
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

public enum PhotoFolder {
    public static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "webp"]
    public static let defaultFolder = "~/Pictures"

    public static func expand(_ folder: String?) -> String {
        let raw = folder?.trimmingCharacters(in: .whitespaces).isEmpty == false ? folder! : defaultFolder
        return NSString(string: raw).expandingTildeInPath
    }

    public static func pictures(in folder: String) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public static func contains(_ path: String, folders: [String]) -> Bool {
        let file = URL(fileURLWithPath: path).standardizedFileURL
        guard extensions.contains(file.pathExtension.lowercased()) else { return false }
        let parent = file.deletingLastPathComponent().path
        return folders.contains { URL(fileURLWithPath: $0).standardizedFileURL.path == parent }
    }
}
