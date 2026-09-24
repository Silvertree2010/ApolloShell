import AppKit
import ApolloBase
import ApolloConfig
import ApolloStyle
import ApolloRuntime
import ApolloProviders
import ApolloControl
import ApolloShellCore

@MainActor
final class LiveShell: WindowHostLink {
    static let usage = "usage: ApolloShell [--config <folder>] [--fixture <file>] [--resources <folder>]"

    struct Options: Equatable {
        var config: URL?
        var resources: URL
        var fixture: URL?

        var dockFallback: URL { resources.appendingPathComponent("render/dock") }
    }

    static func options(_ arguments: [String], executable: URL) -> Options {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        let resources = value("--resources").map { URL(fileURLWithPath: $0) }
            ?? executable.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
        return Options(
            config: value("--config").map { URL(fileURLWithPath: $0).standardizedFileURL },
            resources: resources.standardizedFileURL,
            fixture: value("--fixture").map { URL(fileURLWithPath: $0).standardizedFileURL }
        )
    }

    let options: Options
    let host: WindowHost
    let paths: ConfigPaths
    let settings: SettingsStore
    let overlay = ErrorOverlayModel()
    private(set) var assembly: ShellAssembly?
    private(set) var hotKeys: BindHotKeys?
    private(set) var location: ConfigLocation?
    private(set) var steps: [String] = []
    private var system: SystemProviders?
    private var icons: any AppIconSource = WorkspaceAppIcons()
    private var shell = Record()
    private var overlayWindow: ErrorOverlayWindow?
    private var watcher: FolderWatcher?
    private let debouncer = ReloadDebouncer()
    private var socket: ControlSocketServer?
    private var updates: UpdateController?
    private var crashes: CrashReporter?
    private var reloading = false
    private var watchedFiles: [URL] = []
    var registrar: any HotKeyRegistering = CarbonHotKeys()
    var interactive = true

    init(options: Options, host: WindowHost = WindowHost(), environment: [String: String] = ProcessInfo.processInfo.environment, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.options = options
        self.host = host
        paths = ConfigPaths.standard(environment: environment, home: home, bundleResources: options.resources)
        settings = SettingsStore(file: paths.userConfig.appendingPathComponent("settings.kdl"))
        host.log = Self.log
        host.link = self
        debouncer.fire = { [weak self] in self?.reload() }
    }

    static func log(_ line: String) {
        FileHandle.standardError.write(Data("\(line)\n".utf8))
    }

    static func report(_ diagnostics: [Diagnostic]) {
        for diagnostic in diagnostics { log("\(diagnostic.severity): \(diagnostic.message)") }
    }

    var catalog: ConfigCatalog {
        ConfigCatalog(paths: paths, settings: settings, cliOverride: options.config)
    }

    func activeLocation() -> ConfigLocation {
        catalog.active
    }

    func load(_ location: ConfigLocation) async -> ConfigLoadResult {
        let paths = self.paths
        return await Task.detached {
            let loader = ConfigLoader(fileSystem: DiskFileSystem(), paths: paths, registry: .builtin, filters: .builtin, shellVersion: ShellVersion.current)
            return loader.load(location)
        }.value
    }

    func start() async throws {
        steps.append("settings")
        let assembly = ShellAssembly(host: host, scheduler: RunLoopFlushScheduler(), filterContext: {
            FilterContext(now: Date(), locale: .current, timeZone: .current, services: LayoutFilterServices(keyName: KeyboardLayoutNames.keyName))
        })
        self.assembly = assembly
        installProviders(assembly)
        assembly.runtime.onDiagnostics = { [weak self] diagnostics in
            Self.report(diagnostics)
            self?.overlay.show(diagnostics)
        }
        assembly.runtime.onWarning = { [weak self] diagnostic in
            Self.report([diagnostic])
            self?.overlay.add(diagnostic)
        }
        assembly.runtime.onConfigApplied = { [weak self] _, new in self?.configApplied(new) }
        hotKeys = BindHotKeys(bindings: assembly.bindings, registrar: registrar, trigger: { [weak assembly] id in
            _ = assembly?.runtime.triggerBind(id, event: Record())
        }, warn: { [weak self] diagnostic in
            self?.overlay.add(diagnostic)
        }, publish: { [weak self] list in
            self?.setShell("hotkeys", .list(list))
        })
        steps.append("config")
        var location = activeLocation()
        var result = await load(location)
        var failed: [Diagnostic] = []
        if result.ir == nil {
            failed = result.diagnostics
            location = ConfigLocation(id: "apolloshell-default", root: paths.builtinConfigs.appendingPathComponent("apolloshell-default"), isBuiltin: true)
            result = await load(location)
        }
        if options.config == nil, let ir = result.ir, ir.surfaces.isEmpty {
            Self.log("config \(location.id) has no surfaces yet, falling back to the dock render config")
            location = ConfigLocation(id: "render-dock", root: options.dockFallback, isBuiltin: false)
            result = await load(location)
        }
        result = ConfigLoadResult(ir: result.ir, diagnostics: failed + result.diagnostics, files: result.files)
        self.location = location
        watchedFiles = result.files
        steps.append("styles")
        host.context = makeContext(result.ir)
        steps.append("surfaces")
        refreshScreens()
        shell = Record([("config", .string(location.id)), ("version", .string(ShellVersion.current))])
        guard assembly.runtime.applyLoaded(result, persisted: [:], screens: Array(host.screens.keys).sorted(), shell: shell) else {
            throw RenderError.config("config \(location.root.path) did not load")
        }
        host.observeSpaces()
        ShellScreens.onChange { [weak self] in
            guard let self, let assembly = self.assembly else { return }
            self.refreshScreens()
            guard !self.host.screens.isEmpty else { return }
            assembly.runtime.setScreens(Array(self.host.screens.keys).sorted())
            self.host.screensChanged(self.host.screens)
            self.system?.wm.screensChanged()
        }
        watch()
        steps.append("services")
        if interactive { startServices() }
        steps.append("started")
        assembly.runtime.emit("shell.started", Record())
        Self.log("started: config \(location.root.path), providers \(options.fixture == nil ? "system" : "fixture"), \(host.controllers.count) window(s)")
    }

    private func installProviders(_ assembly: ShellAssembly) {
        if let fixtureURL = options.fixture {
            let fixture = ProviderFixture.load(fixtureURL)
            Self.report(fixture.diagnostics)
            assembly.install(FixtureProvider.all(fixture: fixture, onAction: { action, _, _ in
                Self.log("action \(action) (not run)")
            }))
            icons = FixtureAppIcons()
            return
        }
        let system = SystemProviders(directory: paths.applicationSupport, socketPath: socketPath, polls: [], listens: [], clock: DispatchRuntimeClock())
        self.system = system
        assembly.install(system.providers)
        let wm = system.wm
        host.onReservesChanged = { reserves in wm.setPanelReserves(reserves) }
    }

    var socketPath: String {
        ControlSocketPath.resolve(environment: ProcessInfo.processInfo.environment, home: FileManager.default.homeDirectoryForCurrentUser)
    }

    private func makeContext(_ ir: ConfigIR?) -> RenderContext {
        var sheets: [StyleSheet] = [BaseStyleSheet.sheet]
        if let ir {
            let (loaded, diagnostics) = StyleSheets.load(ir)
            Self.report(diagnostics)
            sheets = loaded
        }
        let dark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let styles = StyleResolver(sheets: sheets, environment: StyleSheets.environment(dark: dark))
        return RenderContext(styles: styles, icons: icons, trigger: { [weak self] handler, identity, event in
            _ = self?.assembly?.runtime.trigger(handler, on: identity, event: event)
        })
    }

    private func configApplied(_ ir: ConfigIR) {
        if host.context != nil, reloading {
            host.restyle(makeContext(ir))
        }
        system?.wm.apply(WMSettings(config: ir))
        hotKeys?.apply(ir.binds)
    }

    private func setShell(_ name: String, _ value: Value) {
        var fields = shell.keys.filter { $0 != name }.map { ($0, shell[$0] ?? .null) }
        fields.append((name, value))
        shell = Record(fields)
        assembly?.store.set(DependencyPath("shell", []), .record(shell))
    }

    private func refreshScreens() {
        let current = ShellScreens.current()
        guard !current.isEmpty else { return }
        host.screens = Dictionary(current.map { ($0.info.key, ScreenGeometry(key: $0.info.key, frame: $0.frame, visible: $0.visibleFrame)) }, uniquingKeysWith: { first, _ in first })
    }

    func watch() {
        guard let location else { return }
        let watcher = FolderWatcher { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.debouncer.poke() } }
        }
        watcher.watch([location.root.path, paths.userConfig.path] + watchedFiles.map { $0.deletingLastPathComponent().path })
        self.watcher = watcher
    }

    func reload() {
        guard let location = activeLocationForReload() else { return }
        Task { @MainActor in
            let result = await load(location)
            self.location = location
            reloading = true
            _ = assembly?.runtime.applyLoaded(result, persisted: [:], screens: Array(host.screens.keys).sorted(), shell: shell)
            reloading = false
        }
    }

    private func activeLocationForReload() -> ConfigLocation? {
        guard let location else { return nil }
        if location.id == "render-dock" { return location }
        _ = settings.reload()
        return activeLocation()
    }

    private func startServices() {
        let machine = MachineState(folder: paths.applicationSupport)
        let crashes = CrashReporter(settings: settings, machine: machine)
        crashes.checkAfterLaunch()
        self.crashes = crashes
        overlayWindow = ErrorOverlayWindow(model: overlay, open: { [weak self] diagnostic in
            self?.openInEditor(diagnostic)
        }, reload: { [weak self] in self?.reload() })
        overlayWindow?.update()
        let control = LiveShellControl(shell: self)
        let server = ControlSocketServer(path: socketPath, service: ControlRouter(shell: control, configs: catalog, themes: ThemeCatalog(paths: paths, settings: settings)))
        do {
            try server.start()
            socket = server
        } catch {
            Self.log("control socket failed: \(error)")
        }
        updates = UpdateController(settings: settings, machine: machine)
    }

    func openInEditor(_ diagnostic: Diagnostic) {
        guard let span = diagnostic.span else { return }
        let url = URL(fileURLWithPath: span.file)
        if let editor = settings.settings.editor, !editor.isEmpty {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [editor, "\(url.path):\(span.start.line)"]
            try? process.run()
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func close(_ surfaceID: String) {
        assembly?.runtime.close(surfaceID)
    }

    func surfaceDidFinishClosing(id: String, screenKey: String) {
        assembly?.runtime.surfaceDidFinishClosing(id: id, screenKey: screenKey)
    }

    func keyPressed(_ chord: String, surfaceID: String, screenKey: String) -> Bool {
        guard let assembly, let canonical = KeyNameTable.canonical(chord),
              let surface = assembly.runtime.surface(surfaceID, screenKey: screenKey) else { return false }
        let handlers = surface.ir.keyHandlers.enumerated().filter { KeyNameTable.canonical($0.element.chord) == canonical }
        guard !handlers.isEmpty else { return false }
        for (index, handler) in handlers {
            _ = assembly.actions.trigger(handler.actions, site: "\(surfaceID)@\(screenKey)#key#\(index)", environment: ActionEnvironment(scope: LocalScope(), surfaceID: surfaceID, screenKey: screenKey, event: Record([("chord", .string(canonical))])))
        }
        return true
    }

    func shutdown() {
        watcher?.stop()
        socket?.stop()
        hotKeys?.removeAll()
        system?.terminate()
    }

    static func run(_ arguments: [String]) -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if SingleInstanceGuard.otherInstanceKeepsRunning() {
            SingleInstanceGuard.showRunningInstance()
            return 0
        }
        let shell = LiveShell(options: options(arguments, executable: URL(fileURLWithPath: arguments[0])))
        Task { @MainActor in
            do {
                try await shell.start()
            } catch {
                log("start failed: \(error)")
                exit(1)
            }
        }
        withExtendedLifetime(shell) { app.run() }
        return 0
    }
}

final class LiveShellControl: ShellControl, @unchecked Sendable {
    private weak var shell: LiveShell?

    init(shell: LiveShell) {
        self.shell = shell
    }

    var shellVersion: String { ShellVersion.current }

    func reload() async -> DiagnosticSummary {
        await MainActor.run {
            shell?.reload()
            let problems = shell?.overlay.problems ?? []
            return DiagnosticSummary(text: problems.map(\.message).joined(separator: "\n"),
                                     errors: problems.filter { $0.severity == .error }.count,
                                     warnings: problems.filter { $0.severity == .warning }.count)
        }
    }

    func surface(_ operation: SurfaceOperation, _ id: String) async throws {
        await MainActor.run {
            guard let runtime = shell?.assembly?.runtime else { return }
            switch operation {
            case .open: runtime.open(id, screenKey: nil)
            case .close: runtime.close(id)
            case .toggle: runtime.toggle(id)
            }
        }
    }

    func windowManager(_ arguments: [String]) async throws -> Value {
        try await MainActor.run {
            guard let wm = shell?.systemWM else { throw ShellControlError("the window manager is not available") }
            return try wm.control(arguments)
        }
    }

    func stats() async throws -> Value {
        await MainActor.run {
            guard let shell, let runtime = shell.assembly?.runtime else { return .null }
            let stats = runtime.stats
            let host = shell.host.stats
            return .record(Record([
                ("windows-created", .number(Double(host.windowsCreated))),
                ("surfaces-built", .number(Double(stats.surfacesBuilt))),
                ("bindings-evaluated", .number(Double(stats.bindingsEvaluated))),
                ("providers-running", .number(Double(stats.providersRunning))),
                ("space-changes", .number(Double(host.spaceChanges))),
            ]))
        }
    }

    func quit() async {
        await MainActor.run {
            shell?.shutdown()
            NSApp.terminate(nil)
        }
    }

    func restart() async {
        await quit()
    }

    func openCommandCenter() async {}

    func run(_ actions: String) async throws -> Value { throw Self.unavailable("run") }
    func evaluate(_ expression: String) async throws -> Value { throw Self.unavailable("eval") }
    func watch(_ expression: String) async throws -> AsyncStream<Value> { throw Self.unavailable("watch") }
    func variable(_ name: String) async throws -> Value { throw Self.unavailable("var") }
    func setVariable(_ name: String, to value: Value) async throws { throw Self.unavailable("set") }
    func emit(_ name: String, event: Value) async throws {
        await MainActor.run {
            let fields: Record = if case .record(let record) = event { record } else { Record() }
            _ = shell?.assembly?.runtime.emit(name, fields)
        }
    }
    func providers() async -> Value { .list([]) }
    func tree(_ surface: String?) async throws -> Value { throw Self.unavailable("tree") }
    func custom(_ request: ControlRequest) async -> ControlReply { .failure("unknown command \(request.cmd)") }

    static func unavailable(_ command: String) -> ShellControlError {
        ShellControlError("'\(command)' is not wired into the shell yet")
    }
}

extension LiveShell {
    var systemWM: WMProvider? { system?.wm }
}
