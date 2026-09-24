import Foundation
import ApolloBase

public struct ConfigLocation: Sendable, Hashable {
    public var id: String
    public var root: URL
    public var isBuiltin: Bool

    public init(id: String, root: URL, isBuiltin: Bool) {
        self.id = id
        self.root = root
        self.isBuiltin = isBuiltin
    }
}

public enum ActiveConfigResolver {
    public static func resolve(
        cliOverride: URL?,
        settings: ShellSettingsFile,
        paths: ConfigPaths,
        fileSystem: any ConfigFileSystem
    ) -> (ConfigLocation, [Diagnostic]) {
        if let cliOverride {
            let resolved = fileSystem.resolvingSymlinks(cliOverride)
            return (ConfigLocation(id: resolved.lastPathComponent, root: resolved, isBuiltin: false), [])
        }
        if let id = settings.config {
            if let location = firstExisting(for: id, paths: paths, fileSystem: fileSystem) {
                return (location, [])
            }
            let diagnostic = Diagnostic(.error, "settings.kdl names config '\(id)' which does not exist, falling back to apolloshell-default")
            return (defaultLocation(paths), [diagnostic])
        }
        if hasShellFile(paths.userConfig, fileSystem: fileSystem) {
            return (ConfigLocation(id: "user", root: paths.userConfig, isBuiltin: false), [])
        }
        return (defaultLocation(paths), [])
    }

    static func defaultLocation(_ paths: ConfigPaths) -> ConfigLocation {
        ConfigLocation(id: "apolloshell-default", root: paths.builtinConfigs.appendingPathComponent("apolloshell-default"), isBuiltin: true)
    }

    static func hasShellFile(_ root: URL, fileSystem: any ConfigFileSystem) -> Bool {
        fileSystem.exists(root.appendingPathComponent("shell.kdl"))
    }

    static func firstExisting(for id: String, paths: ConfigPaths, fileSystem: any ConfigFileSystem) -> ConfigLocation? {
        if id == "user" {
            return hasShellFile(paths.userConfig, fileSystem: fileSystem)
                ? ConfigLocation(id: "user", root: paths.userConfig, isBuiltin: false)
                : nil
        }
        let builtinRoot = paths.builtinConfigs.appendingPathComponent(id)
        if hasShellFile(builtinRoot, fileSystem: fileSystem) {
            return ConfigLocation(id: id, root: builtinRoot, isBuiltin: true)
        }
        if let userRoot = paths.configRoot(for: id), hasShellFile(userRoot, fileSystem: fileSystem) {
            return ConfigLocation(id: id, root: userRoot, isBuiltin: false)
        }
        return nil
    }
}
