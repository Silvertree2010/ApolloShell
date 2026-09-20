import AppKit
import ApolloShellCore
import SwiftUI

/// One symbol of the shell: the image out of the theme, otherwise the built-in
/// SF Symbol.
///
/// Every place that shows a symbol names its id out of `ThemeIconCatalog`.
/// When the theme brings `icons/<id>.png`, that image stands there; otherwise
/// nothing changes.
///
/// Images are loaded once and remembered (`ThemedIconCache`), so that the bar
/// does not read off the disk on every redraw.
struct ThemedIcon: View {
    let id: String
    /// The SF Symbol when the theme brings none. Empty: then the view shows
    /// nothing at all without a theme image (the drawn emblem, say).
    var fallback: String

    @Environment(\.shellStyle) private var style

    init(_ id: String, fallback: String? = nil) {
        self.id = id
        self.fallback = fallback ?? ThemeIconCatalog.standard.descriptor(for: id)?.fallback ?? ""
    }

    var body: some View {
        if let url = style.iconFile(id), let image = ThemedIconCache.image(at: url) {
            // As a template only when the theme asks for it: otherwise a
            // multicolor set would lose its colors.
            Image(nsImage: image)
                .renderingMode(style.tintsThemeIcons ? .template : .original)
                .resizable()
                .scaledToFit()
        } else if !fallback.isEmpty {
            Image(systemName: fallback)
        }
    }
}

/// The loaded theme images, by file and modification time.
///
/// The modification time belongs to the key, so that a theme somebody is
/// working on really does appear anew when it is saved.
@MainActor
enum ThemedIconCache {
    private static var images: [String: NSImage] = [:]

    static func image(at url: URL) -> NSImage? {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? nil
        let key = "\(url.path)|\(modified?.timeIntervalSince1970 ?? 0)"
        if let image = images[key] { return image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        // A theme has no more than a few symbols; the list stays small.
        if images.count > ThemeIconCatalog.standard.icons.count * 2 { images.removeAll() }
        images[key] = image
        return image
    }
}
