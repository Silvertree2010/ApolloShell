import AppKit
import ApolloBase
import ApolloConfig
import ApolloRuntime
import ApolloProviders

@MainActor
final class LiveShell {
    static let usage = "usage: ApolloShell [--config <folder>] [--fixture <file>] [--resources <folder>]"

    struct Options: Equatable {
        var config: URL
        var resources: URL
        var fixture: URL?
    }

    static func options(_ arguments: [String], executable: URL) -> Options {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        let resources = value("--resources").map { URL(fileURLWithPath: $0) }
            ?? executable.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
        let config = value("--config").map { URL(fileURLWithPath: $0) } ?? resources.appendingPathComponent("render/dock")
        return Options(
            config: config.standardizedFileURL,
            resources: resources.standardizedFileURL,
            fixture: value("--fixture").map { URL(fileURLWithPath: $0).standardizedFileURL }
        )
    }

    let options: Options
    let host = WindowHost()
    private var assembly: ShellAssembly?
    private var system: SystemProviders?

    init(options: Options) {
        self.options = options
        host.log = Self.log
    }

    static func log(_ line: String) {
        FileHandle.standardError.write(Data("\(line)\n".utf8))
    }

    static func report(_ diagnostics: [Diagnostic]) {
        for diagnostic in diagnostics { log("\(diagnostic.severity): \(diagnostic.message)") }
    }

    func start() throws {
        let assembly = ShellAssembly(host: host, scheduler: RunLoopFlushScheduler(), filterContext: {
            FilterContext(now: Date(), locale: .current, timeZone: .current, services: DefaultFilterServices())
        })
        self.assembly = assembly
        let icons: any AppIconSource
        if let fixtureURL = options.fixture {
            let fixture = ProviderFixture.load(fixtureURL)
            Self.report(fixture.diagnostics)
            assembly.install(FixtureProvider.all(fixture: fixture, onAction: { action, _, _ in
                Self.log("action \(action) (not run)")
            }))
            icons = FixtureAppIcons()
        } else {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ApolloShell", isDirectory: true)
            let system = SystemProviders(directory: directory, socketPath: nil, polls: [], listens: [], clock: DispatchRuntimeClock())
            self.system = system
            assembly.install(system.providers)
            icons = WorkspaceAppIcons()
        }
        let loaded = ConfigSource.load(options.config, builtinConfigs: options.resources.appendingPathComponent("configs"), id: "live")
        Self.report(loaded.diagnostics)
        guard let ir = loaded.ir else { throw RenderError.config("config \(options.config.path) did not load") }
        let (sheets, sheetDiagnostics) = StyleSheets.load(ir)
        Self.report(sheetDiagnostics)
        let dark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let styles = StyleResolver(sheets: sheets, environment: StyleSheets.environment(dark: dark))
        host.context = RenderContext(styles: styles, icons: icons, trigger: { [weak assembly] handler, identity, event in
            _ = assembly?.runtime.trigger(handler, on: identity, event: event)
        })
        let keys = refreshScreens()
        assembly.apply(ir, screens: keys)
        Self.report(assembly.warnings)
        ShellScreens.onChange { [weak self] in
            guard let self, let assembly = self.assembly else { return }
            let keys = self.refreshScreens()
            guard !keys.isEmpty else { return }
            assembly.runtime.setScreens(keys)
        }
        Self.log("started: config \(options.config.path), providers \(options.fixture == nil ? "system" : "fixture"), \(host.windows.count) window(s)")
    }

    @discardableResult
    private func refreshScreens() -> [String] {
        let current = ShellScreens.current()
        guard !current.isEmpty else { return [] }
        host.screens = Dictionary(current.map { ($0.info.key, $0) }, uniquingKeysWith: { first, _ in first })
        return current.map(\.info.key)
    }

    static func run(_ arguments: [String]) -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let shell = LiveShell(options: options(arguments, executable: URL(fileURLWithPath: arguments[0])))
        do {
            try shell.start()
        } catch {
            log("start failed: \(error)")
            return 1
        }
        withExtendedLifetime(shell) { app.run() }
        return 0
    }
}
