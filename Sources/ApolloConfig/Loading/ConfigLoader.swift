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
    public var keepsAllDefines = false

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
        var included = IncludeExpander.expand(root: location.root, origin: origin, fileSystem: fileSystem, paths: paths)
        collect(included.diagnostics, stage: "include")
        if hasErrors(included.diagnostics) {
            return finish(nil, files: included.files)
        }
        let requires = included.nodes.filter { $0.kdl.name == "require" }
        var featured = RequireStage.run(included.nodes, shellVersion: shellVersion, registry: registry)
        collect(featured.diagnostics, stage: "require")
        if featured.nodes.isEmpty, !included.nodes.isEmpty, hasErrors(featured.diagnostics) {
            return finish(nil, files: included.files)
        }
        included.nodes = []
        let registry = self.registry.addingScriptSources(Self.scriptSourceNames(featured.nodes))
        var used = UseStage.run(featured.nodes, registry: registry)
        featured.nodes = []
        collect(used.diagnostics, stage: "use")
        if used.nodeCount > ConfigLimits.maxExpansionBudget {
            return finish(nil, files: included.files)
        }
        var disabled = DisableStage.run(used.nodes, registry: registry)
        used.nodes = []
        collect(disabled.diagnostics, stage: "disable")
        let templates = TemplateCache()
        let declaredVars = Set(disabled.nodes.compactMap { node -> String? in
            guard node.kdl.name == "var", case .string(let name)? = node.kdl.arguments.first?.scalar else { return nil }
            return name
        })
        let filtered = FilterStage.run(disabled.nodes, registry: registry, templates: templates, declaredVars: declaredVars)
        disabled.nodes = []
        collect(filtered.diagnostics, stage: "filter")
        collect(SchemaStage.run(filtered.nodes, defines: used.defines, registry: registry, templates: templates, declaredVars: declaredVars).diagnostics, stage: "schema")
        let built = IRBuilder.build(
            filtered.nodes,
            defines: used.defines,
            requires: requires,
            location: location,
            files: included.files,
            registry: registry,
            fileSystem: fileSystem,
            paths: paths,
            templates: templates,
            keepsAllDefines: keepsAllDefines
        )
        collect(built.diagnostics, stage: "ir")
        return finish(built.ir, files: included.files)
    }
}
