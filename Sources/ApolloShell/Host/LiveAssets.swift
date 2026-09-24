import AppKit
import ApolloConfig
import ApolloShellCore

@MainActor
final class LiveThemes {
    let folders: [URL]
    private(set) var active: Theme?
    private var activeRoot: URL?
    private var installed: [(theme: Theme, root: URL)] = []
    private var icons = BoundedCache<String, NSImage>(limit: 64)
    private var misses: Set<String> = []
    private(set) var diskReads = 0

    init(folders: [URL]) {
        self.folders = folders
    }

    func reload(activeID: String?) {
        var seen = Set<String>()
        installed = []
        for folder in folders {
            for theme in ThemeLoader.themes(in: folder) where seen.insert(theme.identifier).inserted {
                installed.append((theme, folder))
            }
        }
        let found = activeID.flatMap { id in installed.first { $0.theme.identifier == id } }
        active = found?.theme
        activeRoot = found?.root
        icons = BoundedCache(limit: 64)
        misses = []
    }

    func theme(_ name: String) -> Theme? {
        if let found = installed.first(where: { $0.theme.identifier == name }) { return found.theme }
        return name == "default" ? .standard : nil
    }

    func icon(_ id: String) -> NSImage? {
        if let cached = icons[id] { return cached }
        guard !misses.contains(id) else { return nil }
        guard let theme = active, let root = activeRoot, let file = theme.icons.file(id) else {
            remember(miss: id)
            return nil
        }
        diskReads += 1
        guard let image = SafeImageFile.image(at: file, root: root) else {
            remember(miss: id)
            return nil
        }
        icons[id] = image
        return image
    }

    private func remember(miss id: String) {
        if misses.count >= 256 { misses.removeAll() }
        misses.insert(id)
    }
}

@MainActor
final class ProviderImages {
    var data: @MainActor (ImageRef) -> Data? = { _ in nil }
    private var cache = BoundedCache<ImageRef, NSImage>(limit: 16)

    func image(_ ref: ImageRef) -> NSImage? {
        if let cached = cache[ref] { return cached }
        guard let bytes = data(ref), let image = SafeImageFile.decode(bytes) else { return nil }
        cache[ref] = image
        return image
    }
}
