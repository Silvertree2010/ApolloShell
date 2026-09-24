import AppKit
import Darwin
import ImageIO
import ApolloShellCore

enum SafeImageFile {
    static func data(_ reference: String, root: URL, limits: ThemeLimits = .standard) -> Data? {
        guard case .success(let url) = ThemeAssetResolver.folder(root, limits: limits)(reference) else { return nil }
        return data(at: url, root: root, limits: limits)
    }

    static let maxPixels = 7680 * 4320
    static let maxSide = 16384

    static func data(at url: URL, root: URL, limits: ThemeLimits = .standard) -> Data? {
        guard let folder = realPath(root.path), let resolved = realPath(url.path), resolved.hasPrefix(folder + "/"),
              limits.imageExtensions.contains((resolved as NSString).pathExtension.lowercased()),
              let descriptor = openRegular(resolved)
        else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, Int(info.st_size) <= limits.maxAssetBytes,
              let data = try? handle.read(upToCount: limits.maxAssetBytes + 1), data.count <= limits.maxAssetBytes
        else { return nil }
        return data
    }

    static func openRegular(_ path: String) -> Int32? {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW_ANY | O_CLOEXEC)
        return descriptor >= 0 ? descriptor : nil
    }

    static func realPath(_ path: String) -> String? {
        guard let pointer = realpath(path, nil) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    static func pixelCount(_ data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0, width <= maxSide, height <= maxSide
        else { return nil }
        return width * height
    }

    static func decode(_ data: Data) -> NSImage? {
        guard let pixels = pixelCount(data), pixels <= maxPixels else { return nil }
        return NSImage(data: data)
    }

    static func image(_ reference: String, root: URL) -> NSImage? {
        data(reference, root: root).flatMap(decode)
    }

    static func image(at url: URL, root: URL) -> NSImage? {
        data(at: url, root: root).flatMap(decode)
    }
}
