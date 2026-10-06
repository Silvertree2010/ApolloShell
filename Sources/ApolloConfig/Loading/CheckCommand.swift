import Foundation
import ApolloBase

public enum CheckCommand {
    public static let usage = "usage: apollo check [--fixture <file>] [<folder>]\n\nLoads and checks a config without applying it. Without a folder, checks the active config.\nWith --fixture, also builds every surface with the fixture's provider values and reports\nevery read of a record field that does not exist."

    public enum Exit {
        public static let ok: Int32 = 0
        public static let failure: Int32 = 1
        public static let usage: Int32 = 2
    }

    public static func run(
        arguments: [String],
        environment: [String: String],
        fileSystem: any ConfigFileSystem,
        executableURL: URL,
        fixtureCheck: ((ConfigIR, URL) -> [Diagnostic])? = nil,
        styleCheck: ((ConfigIR) -> [Diagnostic])? = nil
    ) -> (output: String, exitCode: Int32) {
        if arguments.contains(where: { $0 == "--help" || $0 == "-h" }) {
            return (usage, Exit.ok)
        }
        var arguments = arguments
        var fixture: URL?
        if let index = arguments.firstIndex(of: "--fixture") {
            guard fixtureCheck != nil else {
                return ("error: --fixture is not available in this build\n\n" + usage, Exit.usage)
            }
            guard index + 1 < arguments.count else {
                return ("error: --fixture needs a file\n\n" + usage, Exit.usage)
            }
            fixture = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
            arguments.removeSubrange(index...(index + 1))
        }
        if let option = arguments.first(where: { $0.hasPrefix("-") }) {
            return ("error: unknown option '\(option)'\n\n" + usage, Exit.usage)
        }
        guard arguments.count <= 1 else {
            return ("error: check takes at most one folder\n\n" + usage, Exit.usage)
        }
        let home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        let paths = standardPaths(environment: environment, home: home, fileSystem: fileSystem, executableURL: executableURL)
        var diagnostics: [Diagnostic] = []
        let location: ConfigLocation
        if let argument = arguments.first {
            let folder = fileSystem.resolvingSymlinks(URL(fileURLWithPath: argument).standardizedFileURL)
            guard fileSystem.exists(folder) else {
                return render([Diagnostic(.error, "'\(folder.path)' does not exist", code: .checkFolder)], fileSystem: fileSystem, home: home)
            }
            guard fileSystem.isDirectory(folder) else {
                let text = render([Diagnostic(.error, "'\(folder.path)' is not a folder", code: .checkFolder)], fileSystem: fileSystem, home: home).output
                return (text + "\n\n" + usage, Exit.usage)
            }
            location = ActiveConfigResolver.resolve(cliOverride: folder, settings: ShellSettingsFile(), paths: paths, fileSystem: fileSystem).0
        } else {
            let settings = readSettings(paths: paths, fileSystem: fileSystem)
            diagnostics += settings.1
            let resolved = ActiveConfigResolver.resolve(cliOverride: nil, settings: settings.0, paths: paths, fileSystem: fileSystem)
            location = resolved.0
            diagnostics += resolved.1
        }
        if let problem = entryProblem(location, fileSystem: fileSystem) {
            return render(diagnostics + [problem], fileSystem: fileSystem, home: home)
        }
        let loader = ConfigLoader(fileSystem: fileSystem, paths: paths, registry: .builtin, filters: .builtin, shellVersion: ShellVersion.current)
        let result = loader.load(location)
        diagnostics += result.diagnostics
        if let ir = result.ir, let styleCheck { diagnostics += styleCheck(ir) }
        if let fixture, let ir = result.ir, let fixtureCheck {
            guard fileSystem.exists(fixture) else {
                return render(diagnostics + [Diagnostic(.error, "fixture '\(fixture.path)' does not exist", code: .checkFixture)], fileSystem: fileSystem, home: home)
            }
            diagnostics += fixtureCheck(ir, fixture)
        }
        let rendered = render(diagnostics, fileSystem: fileSystem, home: home)
        return (rendered.output, result.ir == nil ? Exit.failure : rendered.exitCode)
    }

    static func standardPaths(environment: [String: String], home: String, fileSystem: any ConfigFileSystem, executableURL: URL) -> ConfigPaths {
        let executable = fileSystem.resolvingSymlinks(executableURL)
        let resources = executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
        var paths = ConfigPaths.standard(environment: environment, home: URL(fileURLWithPath: home), bundleResources: resources)
        if let builtin = environment["APOLLO_BUILTIN_CONFIGS"], !builtin.isEmpty {
            paths.builtinConfigs = URL(fileURLWithPath: builtin).standardizedFileURL
        }
        return paths
    }

    static func readSettings(paths: ConfigPaths, fileSystem: any ConfigFileSystem) -> (ShellSettingsFile, [Diagnostic]) {
        let file = paths.settingsFile
        guard fileSystem.exists(file) else { return (ShellSettingsFile(), []) }
        guard let text = try? fileSystem.read(file) else {
            return (ShellSettingsFile(), [Diagnostic(.warning, "cannot read '\(file.path)', using defaults", code: .checkUnreadable)])
        }
        return ShellSettingsFile.parse(text, file: file.path)
    }

    static func entryProblem(_ location: ConfigLocation, fileSystem: any ConfigFileSystem) -> Diagnostic? {
        let root = location.root
        if location.isBuiltin, !fileSystem.exists(root.appendingPathComponent("shell.kdl")) {
            return Diagnostic(.error, "built-in config '\(location.id)' is missing at '\(root.path)'", code: .checkFolder)
        }
        if fileSystem.isDirectory(root), (try? fileSystem.contentsOfDirectory(root)) == nil {
            return Diagnostic(.error, "cannot read folder '\(root.path)'", code: .checkFolder)
        }
        if !fileSystem.exists(root.appendingPathComponent("shell.kdl")) {
            return Diagnostic(.error, "'\(root.path)' has no shell.kdl", code: .checkFolder)
        }
        return nil
    }

    static func render(_ diagnostics: [Diagnostic], fileSystem: any ConfigFileSystem, home: String) -> (output: String, exitCode: Int32) {
        var cache: [String: String?] = [:]
        let text = DiagnosticFormatter.consoleText(diagnostics, sources: { file in
            if let cached = cache[file] { return cached }
            let loaded = try? fileSystem.read(URL(fileURLWithPath: file))
            cache[file] = loaded
            return loaded
        }, home: home)
        let failed = diagnostics.contains { $0.severity == .error }
        return (text, failed ? Exit.failure : Exit.ok)
    }
}
