import Foundation
import ApolloBase
import ApolloConfig

public struct ConfigEntry: Sendable, Hashable {
    public var id: String
    public var root: URL
    public var isBuiltin: Bool
    public var isActive: Bool
}

public struct ConfigCatalog: Sendable {
    public let paths: ConfigPaths
    public let settings: SettingsStore
    public let cliOverride: URL?
    private let fileSystem: any ConfigFileSystem

    public init(paths: ConfigPaths, settings: SettingsStore, cliOverride: URL? = nil, fileSystem: any ConfigFileSystem = DiskFileSystem()) {
        self.paths = paths
        self.settings = settings
        self.cliOverride = cliOverride
        self.fileSystem = fileSystem
    }

    public var active: ConfigLocation {
        ActiveConfigResolver.resolve(cliOverride: cliOverride, settings: settings.settings, paths: paths, fileSystem: fileSystem).0
    }

    public func list() -> [ConfigEntry] {
        let activeID = active.id
        var entries: [ConfigEntry] = []
        for root in folders(in: paths.builtinConfigs) {
            entries.append(ConfigEntry(id: root.lastPathComponent, root: root, isBuiltin: true, isActive: false))
        }
        if hasShell(paths.userConfig) {
            entries.append(ConfigEntry(id: "user", root: paths.userConfig, isBuiltin: false, isActive: false))
        }
        let taken = Set(entries.map(\.id))
        for root in folders(in: paths.userConfig.appendingPathComponent("configs")) where !taken.contains(root.lastPathComponent) {
            entries.append(ConfigEntry(id: root.lastPathComponent, root: root, isBuiltin: false, isActive: false))
        }
        return entries.map { entry in
            var entry = entry
            entry.isActive = entry.id == activeID && cliOverride == nil
            return entry
        }
    }

    public func select(_ id: String) throws {
        guard list().contains(where: { $0.id == id }) else {
            throw ShellControlError("no config named '\(id)'")
        }
        try settings.apply(.config(id))
    }

    public func fork(_ id: String, as newID: String) throws {
        guard let source = list().first(where: { $0.id == id }) else {
            throw ShellControlError("no config named '\(id)'")
        }
        guard Self.isValidID(newID) else {
            throw ShellControlError("'\(newID)' is not a valid config id (letters, digits, '-', '_', '.', not starting with '.')")
        }
        guard !list().contains(where: { $0.id == newID }) else {
            throw ShellControlError("a config named '\(newID)' already exists")
        }
        guard let target = paths.configRoot(for: newID), !fileSystem.exists(target) else {
            throw ShellControlError("\(newID) already exists in \(paths.userConfig.appendingPathComponent("configs").path)")
        }
        do {
            if source.root.standardizedFileURL == paths.userConfig.standardizedFileURL {
                for child in try fileSystem.contentsOfDirectory(source.root) where !Self.shellOwned.contains(child.lastPathComponent) {
                    try fileSystem.copyItem(child, to: target.appendingPathComponent(child.lastPathComponent))
                }
            } else {
                try fileSystem.copyItem(source.root, to: target)
            }
        } catch {
            throw ShellControlError("could not copy \(source.root.path) to \(target.path): \(error)")
        }
        try settings.apply(.config(newID))
    }

    static let shellOwned: Set<String> = ["configs", "state", "themes", "packages", "settings.kdl", "user.css"]

    static func isValidID(_ id: String) -> Bool {
        guard !id.isEmpty, id != "user", !id.hasPrefix("."), id.count <= 64 else { return false }
        return id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0) }
    }

    private func hasShell(_ root: URL) -> Bool {
        fileSystem.exists(root.appendingPathComponent("shell.kdl"))
    }

    private func folders(in parent: URL) -> [URL] {
        guard let children = try? fileSystem.contentsOfDirectory(parent) else { return [] }
        return children
            .filter { !$0.lastPathComponent.hasPrefix(".") && fileSystem.isDirectory($0) && hasShell($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
