import AppKit
import ApolloShellCore

/// One row of the launcher list: an app, or - after `>` - an action, the
/// calculator's result, a theme or a wallpaper (`LauncherQuery`).
enum LauncherRow: Identifiable {
    case app(AppEntry)
    case action(LauncherAction)
    case calculation(result: String)
    case theme(id: String?, title: String, current: Bool)
    case wallpaper(AppleWallpaper)
    /// A line that only says something ("Type a sum").
    case note(String)

    var id: String {
        switch self {
        case .app(let app): "app:\(app.id)"
        case .action(let action): "action:\(action.rawValue)"
        case .calculation(let result): "calc:\(result)"
        case .theme(let id, _, _): "theme:\(id ?? "")"
        case .wallpaper(let wallpaper): "wallpaper:\(wallpaper.name)"
        case .note(let text): "note:\(text)"
        }
    }

    var app: AppEntry? {
        if case .app(let app) = self { return app }
        return nil
    }
}

/// Apple's wallpapers out of /System/Library/Desktop Pictures: the
/// `.madesktop` entries (macOS fetches the picture itself when it is set),
/// the pictures lying there ready (Sonoma is a plain .heic) and the solid
/// colours. Previews from the folder's `.thumbnails` where there is one.
///
/// A `.madesktop` only names an asset; the picture comes from Apple's
/// servers, and only System Settings starts that download - set by code,
/// macOS shows its default instead (measured 21.09., WallpaperAgent:
/// "WallpaperImageLayerProviderError"). Downloaded ones lie as plain .heic
/// in `~/Library/Application Support/com.apple.mobileAssetDesktop/`; those
/// are set directly, the rest send the user to System Settings.
struct AppleWallpaper: Hashable {
    let name: String
    /// What gets set: the picture itself, `nil` while it is not downloaded.
    let url: URL?
    let thumbnail: URL?

    var isAvailable: Bool { url != nil }

    static let folder = URL(fileURLWithPath: "/System/Library/Desktop Pictures", isDirectory: true)
    static let downloads = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.mobileAssetDesktop", isDirectory: true)

    /// Read on every launcher opening that needs it - one directory listing.
    static func all() -> [AppleWallpaper] {
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

    /// On every screen, as System Settings does. Not downloaded yet: opens
    /// System Settings at Wallpaper instead, where one click fetches it.
    @MainActor
    func apply() -> Bool {
        guard let url else {
            SystemSettings.open(.wallpaper)
            return true
        }
        var ok = true
        for screen in NSScreen.screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            } catch {
                ok = false
            }
        }
        return ok
    }
}
