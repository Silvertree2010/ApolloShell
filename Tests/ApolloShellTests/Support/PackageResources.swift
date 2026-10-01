import Foundation
import ApolloBase
import ApolloConfig

enum PackageResources {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let configs = root.appendingPathComponent("Resources/configs")
    static let dockRender = root.appendingPathComponent("Resources/render/dock")

    static func load(_ folder: URL, id: String = "render-dock", allDefines: Bool = false) -> ConfigLoadResult {
        let paths = ConfigPaths(builtinConfigs: configs, userConfig: folder, applicationSupport: FileManager.default.temporaryDirectory)
        var loader = ConfigLoader(fileSystem: DiskFileSystem(), paths: paths, registry: .builtin, filters: .builtin, shellVersion: ShellVersion.current)
        loader.keepsAllDefines = allDefines
        return loader.load(ConfigLocation(id: id, root: folder, isBuiltin: false))
    }
}
