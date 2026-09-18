import AppKit
import ApolloShellCore
import SwiftUI

/// Ein Symbol der Shell: das Bild aus dem Theme, sonst das eingebaute
/// SF Symbol.
///
/// Jede Stelle, die ein Symbol zeigt, nennt dessen Kennung aus
/// `ThemeIconCatalog`. Bringt das Theme `icons/<kennung>.png` mit, steht dort
/// das Bild; sonst aendert sich nichts.
///
/// Bilder werden einmal geladen und gemerkt (`ThemedIconCache`), damit die
/// Leiste nicht bei jedem Neuzeichnen von der Platte liest.
struct ThemedIcon: View {
    let id: String
    /// Das SF Symbol, wenn das Theme nichts mitbringt. Leer: dann zeigt die
    /// Ansicht ohne Theme-Bild gar nichts (etwa das gezeichnete Emblem).
    var fallback: String

    @Environment(\.shellStyle) private var style

    init(_ id: String, fallback: String? = nil) {
        self.id = id
        self.fallback = fallback ?? ThemeIconCatalog.standard.descriptor(for: id)?.fallback ?? ""
    }

    var body: some View {
        if let url = style.iconFile(id), let image = ThemedIconCache.image(at: url) {
            // Als Schablone nur, wenn das Theme es verlangt: sonst verloere
            // ein mehrfarbiges Set seine Farben.
            Image(nsImage: image)
                .renderingMode(style.tintsThemeIcons ? .template : .original)
                .resizable()
                .scaledToFit()
        } else if !fallback.isEmpty {
            Image(systemName: fallback)
        }
    }
}

/// Geladene Theme-Bilder, nach Datei und Aenderungszeit.
///
/// Die Aenderungszeit gehoert zum Schluessel, damit ein Theme, an dem gerade
/// gearbeitet wird, beim Speichern auch wirklich neu erscheint.
@MainActor
enum ThemedIconCache {
    private static var images: [String: NSImage] = [:]

    static func image(at url: URL) -> NSImage? {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? nil
        let key = "\(url.path)|\(modified?.timeIntervalSince1970 ?? 0)"
        if let image = images[key] { return image }
        guard let image = NSImage(contentsOf: url) else { return nil }
        // Mehr als ein paar Symbole hat ein Theme nicht; die Liste bleibt klein.
        if images.count > ThemeIconCatalog.standard.icons.count * 2 { images.removeAll() }
        images[key] = image
        return image
    }
}
