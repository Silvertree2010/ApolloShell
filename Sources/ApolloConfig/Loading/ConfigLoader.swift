import Foundation
import ApolloBase

public struct ConfigLoadResult: Sendable {
    public var ir: ConfigIR?
    public var diagnostics: [Diagnostic]
    public var files: [URL]

    public init(ir: ConfigIR?, diagnostics: [Diagnostic], files: [URL]) {
        self.ir = ir
        self.diagnostics = diagnostics
        self.files = files
    }
}

public struct ConfigLoader: Sendable {
    let fileSystem: any ConfigFileSystem
    let paths: ConfigPaths
    let registry: SchemaRegistry
    let filters: FilterTable
    let shellVersion: String

    public init(fileSystem: any ConfigFileSystem, paths: ConfigPaths, registry: SchemaRegistry, filters: FilterTable, shellVersion: String) {
        self.fileSystem = fileSystem
        self.paths = paths
        self.registry = registry
        self.filters = filters
        self.shellVersion = shellVersion
    }

    public func load(_ location: ConfigLocation) -> ConfigLoadResult {
        var collector = DiagnosticCollector()
        func collect(_ diagnostics: [Diagnostic], stage: String) {
            for diagnostic in diagnostics {
                collector.add(diagnostic, stage: stage)
            }
        }
        func finish(_ ir: ConfigIR?, files: [URL]) -> ConfigLoadResult {
            let report = collector.finalize()
            return ConfigLoadResult(ir: report.hasErrors ? nil : ir, diagnostics: report.diagnostics, files: files)
        }
        func hasErrors(_ diagnostics: [Diagnostic]) -> Bool {
            diagnostics.contains { $0.severity == .error }
        }

        let origin: FileOrigin = location.isBuiltin ? .builtin(location.id) : .user
        let included = IncludeExpander.expand(root: location.root, origin: origin, fileSystem: fileSystem, paths: paths)
        collect(included.diagnostics, stage: "include")
        if hasErrors(included.diagnostics) {
            return finish(nil, files: included.files)
        }
        let requires = included.nodes.filter { $0.kdl.name == "require" }
        let featured = FeatureStage.run(included.nodes, shellVersion: shellVersion, registry: registry)
        collect(featured.diagnostics, stage: "feature")
        if featured.nodes.isEmpty, !included.nodes.isEmpty, hasErrors(featured.diagnostics) {
            return finish(nil, files: included.files)
        }
        let lets = LetStage.run(featured.nodes, registry: registry, filters: filters)
        collect(lets.diagnostics, stage: "let")
        let used = UseStage.run(lets.nodes, registry: registry)
        collect(used.diagnostics, stage: "use")
        if used.nodeCount > ConfigLimits.maxExpansionBudget {
            return finish(nil, files: included.files)
        }
        let disabled = DisableStage.run(used.nodes, registry: registry)
        collect(disabled.diagnostics, stage: "disable")
        let checked = SchemaStage.run(disabled.nodes, defines: used.defines, registry: registry)
        collect(checked.diagnostics, stage: "schema")
        let built = IRBuilder.build(
            disabled.nodes,
            defines: used.defines,
            requires: requires,
            location: location,
            files: included.files,
            registry: registry,
            fileSystem: fileSystem,
            paths: paths
        )
        collect(built.diagnostics, stage: "ir")
        return finish(built.ir, files: included.files)
    }
}
