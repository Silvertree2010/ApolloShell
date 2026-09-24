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
    let fullscreen: FullscreenMonitor
    let edgeHover = EdgeHoverController()
    private(set) var assembly: ShellAssembly?
    private(set) var hotKeys: BindHotKeys?
    private(set) var location: ConfigLocation?
    private(set) var steps: [String] = []
    private(set) var providerIDs: [String] = []
    private(set) var reloadsApplied = 0
    private var system: SystemProviders?
    private var icons: any AppIconSource = WorkspaceAppIcons()
    private var shell = Record()
    private var overlayWindow: ErrorOverlayWindow?
    private var watcher: FolderWatcher?
    let debouncer = ReloadDebouncer()
    private var socket: ControlSocketServer?
    private var updates: UpdateController?
    private var crashes: CrashReporter?
    private var commandCenter: CommandCenterController?
    private var windowGuard: WindowGuard?
    private var writers: [String: StateWriter] = [:]
    private var reloading = false
    private var reloadGeneration = 0
    private var watchedFiles: [URL] = []
    var registrar: any HotKeyRegistering = CarbonHotKeys()
    var interactive = true
    var currentScreens: @MainActor () -> [String: ScreenGeometry] = {
        Dictionary(ShellScreens.current().map { ($0.info.key, ScreenGeometry(key: $0.info.key, frame: $0.frame, visible: $0.visibleFrame)) }, uniquingKeysWith: { first, _ in first })
    }
    var pointerScreen: @MainActor () -> String? = { ShellScreens.underPointer()?.info.key }

    init(options: Options, host: WindowHost = WindowHost(), environment: [String: String] = ProcessInfo.processInfo.environment, home: URL = FileManager.default.homeDirectoryForCurrentUser, fullscreen: FullscreenMonitor? = nil) {
        self.options = options
        self.host = host
        self.fullscreen = fullscreen ?? FullscreenMonitor.live()
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
        resolveActive().0
    }

    func resolveActive() -> (ConfigLocation, [Diagnostic]) {
        ActiveConfigResolver.resolve(cliOverride: options.config, settings: settings.settings, paths: paths, fileSystem: DiskFileSystem())
    }

    func load(_ location: ConfigLocation) async -> ConfigLoadResult {
        let paths = self.paths
        return await Task.detached {
            let loader = ConfigLoader(fileSystem: DiskFileSystem(), paths: paths, registry: .builtin, filters: .builtin, shellVersion: ShellVersion.current)
            return loader.load(location)
        }.value
    }

    func stateFile(_ location: ConfigLocation) -> URL {
        paths.stateDirectory.appendingPathComponent("\(location.id).kdl")
    }

    func writer(for location: ConfigLocation) -> StateWriter {
        if let writer = writers[location.id] { return writer }
        let writer = StateWriter(file: stateFile(location), fileSystem: DiskFileSystem())
        writers[location.id] = writer
        return writer
    }

    func persisted(for location: ConfigLocation, ir: ConfigIR?) -> [String: Value] {
        guard let ir, let text = try? String(contentsOf: stateFile(location), encoding: .utf8) else { return [:] }
        let (values, diagnostics) = VarStateFile.read(text, file: stateFile(location).path, declarations: ir.vars)
        for diagnostic in diagnostics { overlay.add(diagnostic) }
        return values
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
        assembly.runtime.preferredScreen = { [weak self] in
            guard let self, let key = self.pointerScreen(), self.host.screens[key] != nil else { return nil }
            return key
        }
        hotKeys = BindHotKeys(bindings: assembly.bindings, registrar: registrar, trigger: { [weak assembly] id in
            _ = assembly?.runtime.triggerBind(id, event: Record())
        }, warn: { [weak self] diagnostic in
            self?.overlay.add(diagnostic)
        }, publish: { [weak self] list in
            self?.setShell("hotkeys", .list(list))
        })
        steps.append("config")
        var (location, failed) = resolveActive()
        var result = await load(location)
        if result.ir == nil {
            failed += result.diagnostics
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
        guard assembly.runtime.applyLoaded(result, persisted: persisted(for: location, ir: result.ir), screens: Array(host.screens.keys).sorted(), shell: shell, writer: writer(for: location)) else {
            throw RenderError.config("config \(location.root.path) did not load")
        }
        if !failed.isEmpty { overlay.show(failed + overlay.problems.filter { problem in !failed.contains { $0.message == problem.message } }) }
        host.observeSpaces()
        host.onSpaceChange = { [weak self] in self?.fullscreen.poke() }
        fullscreen.apply = { [weak self] hidden, key in self?.assembly?.runtime.setHiddenByFullscreen(hidden, screenKey: key) }
        fullscreen.setScreens(Array(host.screens.keys))
        setUpEdgeHover()
        ShellScreens.onChange { [weak self] in
            guard let self else { return }
            self.screensDidChange(self.currentScreens())
        }
        watch()
        steps.append("services")
        if interactive { startServices() }
        steps.append("started")
        assembly.runtime.emit("shell.started", Record())
        Self.log("started: config \(location.root.path), providers \(options.fixture == nil ? "system" : "fixture"), \(host.controllers.count) window(s)")
    }

    func screensDidChange(_ screens: [String: ScreenGeometry]) {
        guard let assembly, !screens.isEmpty else { return }
        host.screens = screens
        assembly.runtime.setScreens(Array(screens.keys).sorted())
        host.screensChanged(screens)
        fullscreen.setScreens(Array(screens.keys))
        system?.wm.screensChanged()
        windowGuard?.refresh()
        edgeHover.refresh()
    }

    private func setUpEdgeHover() {
        edgeHover.targets = { [weak self] in self?.host.hoverTargets() ?? [] }
        edgeHover.isFullscreen = { [weak self] key in self?.fullscreen.contains(key) ?? false }
        edgeHover.open = { [weak self] id, screen in self?.assembly?.runtime.open(id, screenKey: screen) }
        edgeHover.close = { [weak self] id in self?.assembly?.runtime.close(id) }
        edgeHover.refresh()
    }

    private func installProviders(_ assembly: ShellAssembly) {
        if let fixtureURL = options.fixture {
            let fixture = ProviderFixture.load(fixtureURL)
            Self.report(fixture.diagnostics)
            let list = FixtureProvider.all(fixture: fixture, onAction: { action, _, _ in
                Self.log("action \(action) (not run)")
            })
            providerIDs = list.map(\.schema.id)
            assembly.install(list)
            icons = FixtureAppIcons()
            return
        }
        let system = SystemProviders(directory: paths.applicationSupport, socketPath: socketPath, polls: [], listens: [], clock: DispatchRuntimeClock())
        self.system = system
        providerIDs = system.providers.map(\.schema.id)
        assembly.install(system.providers)
        let wm = system.wm
        host.onReservesChanged = { [weak self] reserves in
            wm.setPanelReserves(reserves)
            self?.reservesChanged()
        }
    }

    private func reservesChanged() {
        guard interactive else { return }
        let edges = host.reservedEdges()
        if windowGuard == nil, !edges.isEmpty {
            windowGuard = WindowGuard(askForAccess: !onboardingOpen)
            windowGuard?.source = { [weak self] in
                guard let self, self.system?.wm.isEngineRunning != true else { return [:] }
                return self.host.reservedEdges()
            }
        }
        windowGuard?.refresh()
    }

    private var onboardingOpen: Bool {
        host.controllers.values.contains { controller in
            guard controller.surface.ir.kind == "window", controller.surface.isOpen else { return false }
            if case .string(let classes) = controller.surface.property("class") {
                return classes.split(separator: " ").contains("onboarding")
            }
            return false
        }
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
        edgeHover.refresh()
    }

    private func setShell(_ name: String, _ value: Value) {
        var fields = shell.keys.filter { $0 != name }.map { ($0, shell[$0] ?? .null) }
        fields.append((name, value))
        shell = Record(fields)
        assembly?.store.set(DependencyPath("shell", []), .record(shell))
    }

    private func refreshScreens() {
        let current = currentScreens()
        guard !current.isEmpty else { return }
        host.screens = current
    }

    func watch() {
        guard let location else { return }
        let watcher = FolderWatcher { [weak self] paths in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.filesChanged(paths) } }
        }
        watcher.watch([location.root.path, paths.userConfig.path, paths.stateDirectory.path] + watchedFiles.map { $0.deletingLastPathComponent().path })
        self.watcher = watcher
    }

    func filesChanged(_ changed: [String]) {
        let state = paths.stateDirectory.standardizedFileURL.path + "/"
        let onlyState = !changed.isEmpty && changed.allSatisfy { URL(fileURLWithPath: $0).standardizedFileURL.path.hasPrefix(state) }
        if onlyState {
            stateChanged()
        } else {
            debouncer.poke()
        }
    }

    func stateChanged() {
        guard let location, let assembly, let writer = writers[location.id],
              let text = try? String(contentsOf: stateFile(location), encoding: .utf8),
              text != writer.lastWrittenText else { return }
        assembly.vars.applyExternal(text: text)
    }

    @discardableResult
    func reload() -> Task<Void, Never>? {
        guard let location = activeLocationForReload() else { return nil }
        reloadGeneration += 1
        let generation = reloadGeneration
        return Task { @MainActor in
            let result = await load(location)
            guard generation == reloadGeneration else { return }
            if result.ir != nil, Self.shellFileIsEmpty(location) {
                Self.log("shell.kdl of \(location.id) is empty, keeping the last config")
                return
            }
            self.location = location
            if result.ir != nil { watchedFiles = result.files }
            reloading = true
            if assembly?.runtime.applyLoaded(result, persisted: persisted(for: location, ir: result.ir), screens: Array(host.screens.keys).sorted(), shell: shell, writer: writer(for: location)) == true {
                reloadsApplied += 1
            }
            reloading = false
        }
    }

    static func shellFileIsEmpty(_ location: ConfigLocation) -> Bool {
        let file = location.root.appendingPathComponent("shell.kdl")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func activeLocationForReload() -> ConfigLocation? {
        guard let location else { return nil }
        if location.id == "render-dock" { return location }
        _ = settings.reload()
        let (next, diagnostics) = resolveActive()
        for diagnostic in diagnostics { overlay.add(diagnostic) }
        return next
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
        commandCenter = CommandCenterController(entries: { [weak self] in self?.commandCenterEntries() ?? [] }, perform: { [weak self] command in
            self?.perform(command)
        })
        let control = LiveShellControl(shell: self)
        let server = ControlSocketServer(path: socketPath, service: ControlRouter(shell: control, configs: catalog, themes: ThemeCatalog(paths: paths, settings: settings)))
        do {
            try server.start()
            socket = server
        } catch {
            Self.log("control socket failed: \(error)")
        }
        updates = UpdateController(settings: settings, machine: machine)
        fullscreen.observe()
        reservesChanged()
    }

    func commandCenterEntries() -> [MenuEntry] {
        let active = location?.id
        let themes = ThemeCatalog(paths: paths, settings: settings).list()
        var state = CommandCenterState(configs: catalog.list().map { .init(id: $0.id, isActive: $0.id == active) },
                                       themes: themes.map { .init(id: $0.id, issueCount: $0.issueCount, isActive: $0.isActive) })
        state.problemCount = overlay.problems.count
        return CommandCenterModel.build(nil, state: state)
    }

    func perform(_ command: MenuCommand) {
        switch command {
        case .reloadConfig: reload()
        case .showProblems: overlay.show(overlay.problems)
        case .selectConfig(let id):
            do { try catalog.select(id); reload() } catch { overlay.add(Diagnostic(.warning, "\(error)")) }
        case .selectTheme(let id):
            do { try ThemeCatalog(paths: paths, settings: settings).select(id); reload() } catch { overlay.add(Diagnostic(.warning, "\(error)")) }
        case .openConfigFolder: if let location { NSWorkspace.shared.open(location.root) }
        case .openThemesFolder: NSWorkspace.shared.open(paths.themesDirectory)
        case .checkForUpdates: updates?.checkNow()
        case .about:
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        case .quit, .restart:
            shutdown()
            NSApp.terminate(nil)
        case .custom(let name): _ = assembly?.runtime.emit("command-center." + name, Record())
        default: Self.log("command center: \(command) is not wired yet")
        }
    }

    func runActions(_ text: String) async throws -> Value {
        let root = URL(fileURLWithPath: "/ipc")
        let fileSystem = MemoryFileSystem([root.appendingPathComponent("shell.kdl").path: "bind \"f20\" id=\"ipc-run\" {\n\(text)\n}\n"])
        let loader = ConfigLoader(fileSystem: fileSystem, paths: ConfigPaths(builtinConfigs: root, userConfig: root, applicationSupport: root), registry: .builtin, filters: .builtin, shellVersion: ShellVersion.current)
        let result = loader.load(ConfigLocation(id: "ipc", root: root, isBuiltin: false))
        let errors = result.diagnostics.filter { $0.severity == .error }
        guard errors.isEmpty, let actions = result.ir?.binds.first?.actions, let assembly else {
            throw ShellControlError(errors.map(\.message).joined(separator: "\n").isEmpty ? "could not run the actions" : errors.map(\.message).joined(separator: "\n"))
        }
        await assembly.actions.trigger(actions, site: "ipc#run", environment: ActionEnvironment())?.value
        return .null
    }

    func compiled(_ expression: String) throws -> CompiledValue {
        let span = SourceSpan.synthetic("ipc")
        switch ExpressionParser.parseTemplate("{" + expression + "}", span: span) {
        case .success(let template): return CompiledValue(template: template, dependencies: template.dependencies(locals: []), span: span)
        case .failure(let diagnostic): throw ShellControlError(diagnostic.message)
        }
    }

    func evaluate(_ expression: String) throws -> Value {
        guard let assembly else { throw LiveShellControl.unavailable("eval") }
        let value = try compiled(expression)
        var result: Value = .null
        let handle = assembly.bindings.bind(value, scope: LocalScope(), active: true) { result = $0 }
        handle.cancel()
        return result
    }

    func watchExpression(_ expression: String) throws -> AsyncStream<Value> {
        guard let assembly else { throw LiveShellControl.unavailable("watch") }
        let value = try compiled(expression)
        let (stream, continuation) = AsyncStream<Value>.makeStream()
        let handle = assembly.bindings.bind(value, scope: LocalScope(), active: true) { continuation.yield($0) }
        let box = HandleBox(handle)
        continuation.onTermination = { _ in
            Task { @MainActor in box.handle?.cancel() }
        }
        return stream
    }

    func variable(_ name: String) throws -> Value {
        guard let vars = assembly?.vars, vars.isDeclared(name) else { throw ShellControlError("no var named '\(name)'") }
        return vars.value(name)
    }

    func setVariable(_ name: String, _ value: Value) throws {
        guard let vars = assembly?.vars, vars.isDeclared(name) else { throw ShellControlError("no var named '\(name)'") }
        guard vars.set(name, value) else { throw ShellControlError("var '\(name)' cannot be set to this value") }
    }

    func providerValues() -> Value {
        guard let store = assembly?.store else { return .record(Record()) }
        return .record(Record(providerIDs.sorted().map { ($0, store.value(DependencyPath($0, []))) }))
    }

    func tree(_ surfaceID: String?) throws -> Value {
        let controllers = host.controllers.keys.sorted().compactMap { host.controllers[$0] }
            .filter { surfaceID == nil || $0.surface.id == surfaceID }
        if let surfaceID, controllers.isEmpty { throw ShellControlError("unknown surface '\(surfaceID)'") }
        return .list(controllers.map { controller in
            let surface = controller.surface
            return .record(Record([
                ("surface", .string(surface.id)), ("screen", .string(surface.screenKey)), ("kind", .string(surface.ir.kind)),
                ("open", .bool(surface.isOpen)), ("visible", .bool(surface.isVisible)),
                ("children", .list(surface.root.map(Self.node))),
            ]))
        })
    }

    static func node(_ element: ElementInstance) -> Value {
        .record(Record([
            ("kind", .string(element.kind)),
            ("identity", .string(String(describing: element.identity))),
            ("children", .list(element.children.map(node))),
        ]))
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
        edgeHover.stop()
        fullscreen.stop()
        commandCenter?.remove()
        commandCenter = nil
        assembly?.vars.flushPendingSaves()
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
        let task = await MainActor.run { shell?.reload() }
        await task?.value
        return await MainActor.run {
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

    func openCommandCenter() async {
        await MainActor.run { shell?.commandCenterPopUp() }
    }

    @MainActor
    private func live(_ command: String) throws -> LiveShell {
        guard let shell else { throw Self.unavailable(command) }
        return shell
    }

    func run(_ actions: String) async throws -> Value {
        let shell = try await live("run")
        return try await shell.runActions(actions)
    }

    func evaluate(_ expression: String) async throws -> Value {
        try await MainActor.run { try live("eval").evaluate(expression) }
    }

    func watch(_ expression: String) async throws -> AsyncStream<Value> {
        try await MainActor.run { try live("watch").watchExpression(expression) }
    }

    func variable(_ name: String) async throws -> Value {
        try await MainActor.run { try live("get").variable(name) }
    }

    func setVariable(_ name: String, to value: Value) async throws {
        try await MainActor.run { try live("set").setVariable(name, value) }
    }
    func emit(_ name: String, event: Value) async throws {
        await MainActor.run {
            let fields: Record = if case .record(let record) = event { record } else { Record() }
            _ = shell?.assembly?.runtime.emit(name, fields)
        }
    }
    func providers() async -> Value {
        await MainActor.run { shell?.providerValues() ?? .record(Record()) }
    }

    func tree(_ surface: String?) async throws -> Value {
        try await MainActor.run { try live("tree").tree(surface) }
    }
    func custom(_ request: ControlRequest) async -> ControlReply { .failure("unknown command \(request.cmd)") }

    static func unavailable(_ command: String) -> ShellControlError {
        ShellControlError("'\(command)' is not wired into the shell yet")
    }
}

extension LiveShell {
    var systemWM: WMProvider? { system?.wm }

    func commandCenterPopUp() {
        commandCenter?.popUpUnderPointer()
    }
}

@MainActor
final class HandleBox {
    var handle: BindingHandle?

    init(_ handle: BindingHandle) {
        self.handle = handle
    }
}
