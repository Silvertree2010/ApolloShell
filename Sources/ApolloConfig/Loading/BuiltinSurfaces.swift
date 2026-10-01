import Foundation
import ApolloBase
import ApolloKDL

public enum BuiltinSurfaces {
    public static let folderName = "builtin"
    public static let marketplaceID = "marketplace"

    public static func folder(_ paths: ConfigPaths) -> URL {
        paths.builtinConfigs.deletingLastPathComponent().appendingPathComponent(folderName)
    }

    public static func load(paths: ConfigPaths, fileSystem: any ConfigFileSystem, shellVersion: String) -> ConfigLoadResult {
        let root = folder(paths)
        var loader = ConfigLoader(fileSystem: fileSystem, paths: paths, registry: .builtin, filters: .builtin, shellVersion: shellVersion)
        loader.keepsAllDefines = true
        return loader.load(ConfigLocation(id: folderName, root: root, isBuiltin: false))
    }

    public static func marketplaceEnabled(_ ir: ConfigIR) -> Bool {
        for block in (ir.blocks[marketplaceID] ?? []).reversed() {
            for node in block.nodes.reversed() {
                if let property = node.property("enabled"), case .bool(let flag) = property.value.scalar {
                    return flag
                }
            }
        }
        return true
    }

    public static func merge(_ builtin: ConfigIR, into ir: ConfigIR) -> ConfigIR {
        var merged = ir
        let surfaceIDs = Set(ir.surfaces.map(\.id))
        let varNames = Set(ir.vars.map(\.name))
        merged.surfaces += builtin.surfaces.filter { !surfaceIDs.contains($0.id) }
        merged.vars += builtin.vars.filter { !varNames.contains($0.name) }
        for (name, define) in builtin.defines where merged.defines[name] == nil {
            merged.defines[name] = define
        }
        merged.styleSheets = builtin.styleSheets + ir.styleSheets
        return merged
    }

    public static func apply(_ result: ConfigLoadResult, builtin: () -> ConfigLoadResult) -> ConfigLoadResult {
        guard let ir = result.ir, marketplaceEnabled(ir) else { return result }
        let loaded = builtin()
        guard let builtinIR = loaded.ir else {
            let notes = loaded.diagnostics.map { Diagnostic(.warning, "built-in Marketplace did not load: \($0.message)", span: $0.span, code: .builtinMarketplace) }
            return ConfigLoadResult(ir: ir, diagnostics: result.diagnostics + notes, files: result.files)
        }
        return ConfigLoadResult(ir: merge(builtinIR, into: ir), diagnostics: result.diagnostics, files: result.files)
    }
}
