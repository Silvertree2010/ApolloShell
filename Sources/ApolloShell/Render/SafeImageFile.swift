import AppKit
import Darwin
import ApolloShellCore

enum SafeImageFile {
    static func data(_ reference: String, root: URL, limits: ThemeLimits = .standard) -> Data? {
        guard case .success(let url) = ThemeAssetResolver.folder(root, limits: limits)(reference) else { return nil }
        return data(at: url, root: root, limits: limits)
    }

    static func data(at url: URL, root: URL, limits: ThemeLimits = .standard) -> Data? {
        let folder = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(folder),
              limits.imageExtensions.contains(resolved.pathExtension.lowercased()) else { return nil }
        let descriptor = open(resolved.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, Int(info.st_size) <= limits.maxAssetBytes,
              let data = try? handle.read(upToCount: limits.maxAssetBytes + 1), data.count <= limits.maxAssetBytes
        else { return nil }
        return data
    }

    static func image(_ reference: String, root: URL) -> NSImage? {
        data(reference, root: root).flatMap(NSImage.init(data:))
    }

    static func image(at url: URL, root: URL) -> NSImage? {
        data(at: url, root: root).flatMap(NSImage.init(data:))
    }
}
