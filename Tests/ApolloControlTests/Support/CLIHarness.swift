import Foundation
import ApolloConfig
@testable import ApolloControl

final class OutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var outLines: [String] = []
    private var errLines: [String] = []

    func out(_ text: String) { lock.withLock { outLines.append(text) } }
    func err(_ text: String) { lock.withLock { errLines.append(text) } }

    var stdout: [String] { lock.withLock { outLines } }
    var stderr: [String] { lock.withLock { errLines } }
}

struct CLIRun {
    var exitCode: Int32
    var stdout: [String]
    var stderr: [String]
}

final class CLIHarness: @unchecked Sendable {
    let folder = TempFolder()
    let shell = FakeShell()
    let paths: ConfigPaths
    let settings: SettingsStore
    let server: ControlSocketServer
    private let checkLog = LockedBox<[[String]]>([])

    var checkCalls: [[String]] { checkLog.value }

    init() throws {
        paths = ConfigPaths(
            builtinConfigs: folder.path("bundle/configs"),
            userConfig: folder.path("cfg"),
            applicationSupport: folder.path("support")
        )
        let files = FileManager.default
        for id in ["apolloshell-default", "launcher-only"] {
            let root = paths.builtinConfigs.appendingPathComponent(id)
            try files.createDirectory(at: root, withIntermediateDirectories: true)
            try "panel \"\(id)\"\n".write(to: root.appendingPathComponent("shell.kdl"), atomically: true, encoding: .utf8)
        }
        try files.createDirectory(at: paths.themesDirectory, withIntermediateDirectories: true)
        try files.createDirectory(at: paths.legacyThemesDirectory, withIntermediateDirectories: true)
        try ":root { --apollo-accent: #ff0000; }\n".write(to: paths.themesDirectory.appendingPathComponent("Nord.css"), atomically: true, encoding: .utf8)
        try ":root { --apollo-accent: #00ff00; }\n".write(to: paths.legacyThemesDirectory.appendingPathComponent("Old.css"), atomically: true, encoding: .utf8)
        settings = SettingsStore(file: paths.settingsFile)
        let router = ControlRouter(
            shell: shell,
            configs: ConfigCatalog(paths: paths, settings: settings),
            themes: ThemeCatalog(paths: paths, settings: settings)
        )
        server = ControlSocketServer(path: folder.socketPath, service: router)
        try server.start()
    }

    func run(_ arguments: [String], socket: String? = nil) -> CLIRun {
        let capture = OutputCapture()
        let code = cli(socket: socket).run(arguments, out: capture.out, err: capture.err)
        return CLIRun(exitCode: code, stdout: capture.stdout, stderr: capture.stderr)
    }

    func cli(socket: String? = nil) -> ApolloCLI {
        ApolloCLI(
            version: "0.2.0-cli",
            transport: SocketTransport(path: socket ?? folder.socketPath),
            check: { [weak self] arguments in
                self?.checkLog.value.append(arguments)
                return (arguments.first == "broken" ? "error: broken\n" : "", arguments.first == "broken" ? 1 : 0)
            }
        )
    }

    deinit {
        server.stop()
        folder.remove()
    }
}
