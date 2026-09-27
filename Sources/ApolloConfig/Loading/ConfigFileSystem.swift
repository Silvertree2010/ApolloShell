import Foundation

public protocol ConfigFileSystem: Sendable {
    func read(_ url: URL) throws -> String
    func contentsOfDirectory(_ url: URL) throws -> [URL]
    func exists(_ url: URL) -> Bool
    func isDirectory(_ url: URL) -> Bool
    func resolvingSymlinks(_ url: URL) -> URL
    func write(_ text: String, to url: URL) throws
    func copyItem(_ source: URL, to destination: URL) throws
}

public struct ConfigFileSystemError: Error, Sendable, Hashable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }
}

public struct DiskFileSystem: ConfigFileSystem {
    public init() {}

    public static let maxReadBytes = 1 << 20

    public func read(_ url: URL) throws -> String {
        let resolved = url.resolvingSymlinksInPath()
        let attributes = try FileManager.default.attributesOfItem(atPath: resolved.path)
        guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
            throw ConfigFileSystemError("\(url.path) is not a regular file")
        }
        let handle = try FileHandle(forReadingFrom: resolved)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maxReadBytes + 1) ?? Data()
        guard data.count <= Self.maxReadBytes else {
            return String(decoding: data, as: UTF8.self)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ConfigFileSystemError("\(url.path) is not UTF-8 text")
        }
        return text
    }

    public func contentsOfDirectory(_ url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    public func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    public func resolvingSymlinks(_ url: URL) -> URL {
        url.resolvingSymlinksInPath()
    }

    public func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    public func copyItem(_ source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
    }
}

public final class MemoryFileSystem: ConfigFileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: String]
    private var directories: Set<String>

    public init(_ files: [String: String] = [:]) {
        self.files = files
        var directories: Set<String> = []
        for path in files.keys {
            var url = URL(fileURLWithPath: path).deletingLastPathComponent()
            while url.path != "/", !directories.contains(url.path) {
                directories.insert(url.path)
                url = url.deletingLastPathComponent()
            }
        }
        self.directories = directories
    }

    public func read(_ url: URL) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let text = files[url.path] else {
            throw ConfigFileSystemError("no file at \(url.path)")
        }
        return text
    }

    public func contentsOfDirectory(_ url: URL) throws -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        let prefix = url.path.hasSuffix("/") ? url.path : url.path + "/"
        var names: Set<String> = []
        for path in files.keys where path.hasPrefix(prefix) {
            if let first = path.dropFirst(prefix.count).split(separator: "/").first {
                names.insert(String(first))
            }
        }
        for path in directories where path.hasPrefix(prefix) {
            let remainder = path.dropFirst(prefix.count)
            if !remainder.isEmpty, let first = remainder.split(separator: "/").first {
                names.insert(String(first))
            }
        }
        return names.sorted().map { url.appendingPathComponent($0) }
    }

    public func exists(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return files[url.path] != nil || directories.contains(url.path)
    }

    public func isDirectory(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return directories.contains(url.path)
    }

    public func resolvingSymlinks(_ url: URL) -> URL {
        url.standardizedFileURL
    }

    public func write(_ text: String, to url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        files[url.path] = text
        var parent = url.deletingLastPathComponent()
        while parent.path != "/", !directories.contains(parent.path) {
            directories.insert(parent.path)
            parent = parent.deletingLastPathComponent()
        }
    }

    public func copyItem(_ source: URL, to destination: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let text = files[source.path] else {
            throw ConfigFileSystemError("no file at \(source.path)")
        }
        files[destination.path] = text
        var parent = destination.deletingLastPathComponent()
        while parent.path != "/", !directories.contains(parent.path) {
            directories.insert(parent.path)
            parent = parent.deletingLastPathComponent()
        }
    }
}
