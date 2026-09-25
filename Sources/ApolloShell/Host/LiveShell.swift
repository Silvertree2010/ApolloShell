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
    let home: URL
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
    let debouncer: ReloadDebouncer
    private var socket: ControlSocketServer?
    private var updates: UpdateController?
    private var crashes: CrashReporter?
    private var commandCenter: CommandCenterController?
    private var appliedTheme: String??
    private var commandCenterHandlers: [String: (actions: [ActionIR], locals: [String: Value])] = [:]
    private var windowGuard: WindowGuard?
    private var writers: [String: StateWriter] = [:]
    private var reloading = false
    private var reloadGeneration = 0
    private var latestReload: Task<Void, Never>?
    private var watchedFiles: [URL] = []
    private(set) var watchedPaths: [String] = []
    private(set) var shutdowns = 0
    private var termination: TerminationWatch?
    private var environmentObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var appearanceObservation: NSKeyValueObservation?
    private var lastIR: ConfigIR?
    private var lastDark: Bool?
    let keyNames = KeyNameSource()
    let themes: LiveThemes
    let providerImages = ProviderImages()
    private(set) var recordings = 0
    var accessibility: @MainActor () -> LiveAccessibility = { LiveAccessibility.current() }
    let toasts = ToastCenter()
    var isDark: @MainActor () -> Bool = { NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
    var terminateApp: @MainActor () -> Void = { NSApp.terminate(nil) }
    var relaunch: @MainActor (URL, Int32) -> Void = LiveShell.relaunchAfterExit
    var registrar: any HotKeyRegistering = CarbonHotKeys()
    var legacyDefaults: (String) -> Any? = { UserDefaults.standard.object(forKey: $0) }
    private(set) var legacyNotes: [Diagnostic] = []
    private(set) var freshInstall = false
    var loginItem = LoginItem.live()
    let globalEffects = GlobalActionEffects()
    let firstWeekday = FirstWeekdaySetting()
    var interactive = true
    var currentScreens: @MainActor () -> [String: ScreenGeometry] = {
        Dictionary(ShellScreens.current().map { ($0.info.key, ScreenGeometry(key: $0.info.key, frame: $0.frame, visible: $0.visibleFrame, name: $0.info.name, notch: $0.screen.safeAreaInsets.top > 0)) }, uniquingKeysWith: { first, _ in first })
    }
    var pointerScreen: @MainActor () -> String? = { ShellScreens.underPointer()?.info.key }

    init(options: Options, host: WindowHost = WindowHost(), environment: [String: String] = ProcessInfo.processInfo.environment, home: URL = FileManager.default.homeDirectoryForCurrentUser, fullscreen: FullscreenMonitor? = nil, debouncer: ReloadDebouncer? = nil) {
        self.options = options
        self.debouncer = debouncer ?? ReloadDebouncer()
        self.host = host
        self.fullscreen = fullscreen ?? FullscreenMonitor.live()
        self.home = home
        paths = ConfigPaths.standard(environment: environment, home: home, bundleResources: options.resources)
        settings = SettingsStore(file: paths.userConfig.appendingPathComponent("settings.kdl"))
        themes = LiveThemes(folders: [paths.themesDirectory, paths.legacyThemesDirectory])
        host.log = Self.log
        host.link = self
        self.debouncer.fire = { [weak self] in self?.reload() }
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
            return BuiltinSurfaces.apply(loader.load(location)) {
                BuiltinSurfaces.load(paths: paths, fileSystem: DiskFileSystem(), shellVersion: ShellVersion.current)
            }
        }.value
    }

    var marketplaceEnabled: Bool {
        lastIR.map(BuiltinSurfaces.marketplaceEnabled) ?? false
    }

    func openMarketplace() {
        guard marketplaceEnabled, lastIR?.surface(BuiltinSurfaces.marketplaceID) != nil else {
            Self.log("marketplace.open: the Marketplace is switched off in this config")
            return
        }
        assembly?.runtime.open(BuiltinSurfaces.marketplaceID, screenKey: nil)
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

    func importLegacySettings() {
        let disk = DiskFileSystem()
        guard LegacyImport.isNeeded(paths: paths, fileSystem: disk) else { return }
        let result = LegacyImport.run(paths: paths, fileSystem: disk, defaults: legacyDefaults)
        legacyNotes = result.diagnostics
        Self.log("imported the 0.1.4.2 settings from \(LegacyImport.settingsJSON(paths).path)")
        Self.report(result.diagnostics)
        _ = settings.reload()
    }

    func start() async throws {
        steps.append("settings")
        freshInstall = LegacyImport.freshInstall(paths: paths, fileSystem: DiskFileSystem())
        importLegacySettings()
        for folder in [paths.stateDirectory, paths.themesDirectory] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let names = keyNames
        let weekday = firstWeekday
        let assembly = ShellAssembly(host: host, scheduler: RunLoopFlushScheduler(), filterContext: {
            FilterContext(now: Date(), locale: .current, timeZone: .current, services: LayoutFilterServices(keyName: { names.name($0) }, firstWeekday: weekday))
        })
        self.assembly = assembly
        assembly.actions.register("osd.show", OSDShowAction(shell: self))
        assembly.actions.register("notify", NotifyAction(center: toasts))
        assembly.actions.register("toast.dismiss", ToastDismissAction(center: toasts))
        assembly.actions.register("marketplace.open", MarketplaceOpenAction(shell: self))
        assembly.actions.register("shell.set-login-item", LoginItemAction(shell: self))
        assembly.actions.register("command-center.open", ClosureAction { [weak self] _ in self?.commandCenterPopUp() })
        registerGlobalActions(assembly)
        toasts.runtime = assembly.runtime
        host.publishSize = { [weak assembly] id, screen, size in
            assembly?.runtime.setSurfaceSize(id, screenKey: screen, width: Double(size.width), height: Double(size.height))
        }
        toasts.targetScreen = { [weak self] in
            guard let self else { return nil }
            if let key = self.pointerScreen(), self.host.screens[key] != nil { return key }
            return Self.screenOrder(self.host.screens).first
        }
        installProviders(assembly)
        assembly.runtime.onDiagnostics = { [weak self] diagnostics in
            Self.report(diagnostics)
            self?.overlay.show(diagnostics)
        }
        assembly.onWarning = { [weak self] diagnostic in
            guard diagnostic.severity != .note else { return }
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
        failed = legacyNotes + failed
        var result = await load(location)
        if result.ir == nil {
            failed += result.diagnostics
            location = ConfigLocation(id: "apolloshell-default", root: paths.builtinConfigs.appendingPathComponent("apolloshell-default"), isBuiltin: true)
            result = await load(location)
        }
        result = ConfigLoadResult(ir: result.ir, diagnostics: failed + result.diagnostics, files: result.files)
        self.location = location
        watchedFiles = result.files
        steps.append("styles")
        host.context = makeContext(result.ir)
        steps.append("surfaces")
        refreshScreens()
        publishScreens(host.screens)
        shell = Record([("config", .string(location.id)), ("version", .string(ShellVersion.current)), ("fresh-install", .bool(freshInstall))] + loginItemFields() + catalogFields() + [
            ("features", .list(SchemaRegistry.builtin.features.keys.sorted().map(Value.string))),
            ("install-kind", .string(InstallKind.detect(resourcesURL: Bundle.main.resourceURL) == .homebrew ? "homebrew" : "dmg")),
            ("update", updateField()),
        ])
        applyFirstWeekday(result.ir)
        guard assembly.runtime.applyLoaded(result, persisted: persisted(for: location, ir: result.ir), screens: Self.screenOrder(host.screens), shell: shell, writer: writer(for: location)) else {
            throw RenderError.config("config \(location.root.path) did not load")
        }
        host.observeSpaces()
        host.onSpaceChange = { [weak self] in self?.fullscreen.poke() }
        fullscreen.apply = { [weak self] hidden, key in
            self?.assembly?.runtime.setHiddenByFullscreen(hidden, screenKey: key)
            _ = self?.assembly?.runtime.emit("fullscreen.changed", Record([("screen", .string(key)), ("active", .bool(hidden))]))
        }
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

    func applyFirstWeekday(_ ir: ConfigIR?) {
        switch ir?.blocks["clock"]?.last?.compiled["first-weekday"]?.template {
        case .literal(let value)?, .whole(.literal(.string(let value)))?: firstWeekday.value = value
        default: firstWeekday.value = "system"
        }
    }

    func publishScreens(_ screens: [String: ScreenGeometry]) {
        guard let store = assembly?.store else { return }
        for (key, screen) in screens {
            store.set(DependencyPath("screen:" + key, []), .record(Record([
                ("id", .string(key)), ("name", .string(screen.name ?? key)), ("main", .bool(screen.frame.origin == .zero)),
                ("width", .number(Double(screen.frame.width))), ("height", .number(Double(screen.frame.height))), ("notch", .bool(screen.notch)),
            ])))
        }
    }

    static func screenOrder(_ screens: [String: ScreenGeometry]) -> [String] {
        func primary(_ key: String) -> Bool { screens[key]?.frame.origin == .zero }
        return screens.keys.sorted { a, b in
            primary(a) != primary(b) ? primary(a) : a < b
        }
    }

    func screensDidChange(_ screens: [String: ScreenGeometry]) {
        guard let assembly, !screens.isEmpty else { return }
        host.screens = screens
        publishScreens(screens)
        assembly.runtime.setScreens(Self.screenOrder(screens))
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
        host.onOpenChanged = { [weak self] in self?.edgeHover.openChanged() }
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
        let marketplace = SystemMarketplaceHost(paths: paths, settings: settings)
        marketplace.onThemesChanged = { [weak self] in
            self?.themes.invalidate()
            self?.reload()
        }
        let system = SystemProviders(directory: paths.applicationSupport, socketPath: socketPath, polls: [], listens: [], marketplace: marketplace, clock: DispatchRuntimeClock())
        self.system = system
        providerImages.data = Self.imageData(system.providers)
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
        let system = isDark()
        lastDark = system
        themes.refresh(activeID: settings.settings.theme)
        let appearance: Appearance = system ? .dark : .light
        let theme = themes.active
        let dark = theme.map { ThemeTokenBridge.effectiveAppearance(theme: $0, system: appearance) == .dark } ?? system
        let tokens = theme.map { ThemeTokenBridge.environment(for: $0, appearance: appearance) } ?? .empty
        let themeValue = ThemeRoot.value(theme: theme, tokens: tokens, dark: dark)
        if let store = assembly?.store, store.value(DependencyPath("theme", [])) != themeValue {
            store.set(DependencyPath("theme", []), themeValue)
        }
        let root = location?.root
        let environment = StyleSheets.liveEnvironment(dark: dark, tokens: tokens, accessibility: accessibility())
        let styles = StyleResolver(sheets: sheets, environment: environment, assetRoot: root)
        let context = RenderContext(styles: styles, icons: icons, trigger: { [weak self] handler, identity, event in
            _ = self?.assembly?.runtime.trigger(handler, on: identity, event: event)
        })
        context.configRoot = root
        let themes = self.themes, images = providerImages
        context.theme = { themes.theme($0) }
        context.themeIcon = { themes.icon($0) }
        context.imageValue = { images.image($0) }
        context.onRecording = { [weak self] on in self?.recording(on) }
        if let assembly { context.connectLive(assembly) }
        return context
    }

    private func configApplied(_ ir: ConfigIR) {
        lastIR = ir
        let theme = settings.settings.theme
        if let appliedTheme, appliedTheme != theme {
            _ = assembly?.runtime.emit("theme.changed", Record([("id", theme.map(Value.string) ?? .null)]))
        }
        appliedTheme = theme
        let catalog = catalogFields()
        if catalog.contains(where: { shell[$0.0] != $0.1 }) { setShell(catalog) }
        applyCommandCenterVisibility(ir)
        if host.context != nil, reloading {
            host.restyle(makeContext(ir))
        }
        system?.wm.apply(WMSettings(config: ir))
        hotKeys?.apply(ir.binds)
        edgeHover.refresh()
    }

    private func setShell(_ name: String, _ value: Value) {
        setShell([(name, value)])
    }

    private func setShell(_ changes: [(String, Value)]) {
        let names = Set(changes.map(\.0))
        let fields = shell.keys.filter { !names.contains($0) }.map { ($0, shell[$0] ?? .null) } + changes
        shell = Record(fields)
        assembly?.store.set(DependencyPath("shell", []), .record(shell))
    }

    func catalogFields() -> [(String, Value)] {
        let configs = catalog.list().map { entry in
            Value.record(Record([("id", .string(entry.id)), ("name", .string(entry.id)), ("source", .string(entry.isBuiltin ? "builtin" : "user"))]))
        }
        var seen: Set<String> = []
        var themes: [Value] = []
        for folder in [paths.themesDirectory, paths.legacyThemesDirectory] {
            for theme in ThemeLoader.themes(in: folder) where seen.insert(theme.identifier).inserted {
                themes.append(.record(Record([
                    ("id", .string(theme.identifier)), ("name", .string(theme.title)), ("author", .string(theme.author)),
                    ("description", .string(theme.details)), ("issues", .list(theme.issues.map { .string($0.description) })),
                ])))
            }
        }
        return [("configs", .list(configs)), ("themes", .list(themes))]
    }

    func updateField() -> Value {
        let status = updates?.status ?? .idle
        let name: String
        var version: Value = .null
        var error: Value = .null
        switch status {
        case .idle, .upToDate: name = "idle"
        case .checking: name = "checking"
        case .available(let value): name = "available"; version = .string(value)
        case .ready(let value): name = "ready"; version = .string(value)
        case .failed(let message): name = "failed"; error = .string(message)
        case .unavailable: name = "unavailable"
        }
        return .record(Record([
            ("status", .string(name)), ("version", version), ("notes-url", updates?.releaseNotes.map { .string($0.absoluteString) } ?? .null),
            ("last-check", updates?.lastCheck.map(Value.date) ?? .null), ("error", error),
        ]))
    }

    private func loginItemFields() -> [(String, Value)] {
        let state = loginItem.state
        return [
            ("login-item", .bool(state.isOn)),
            ("login-item-available", .bool(state.canToggle)),
            ("login-item-note", (loginItem.error ?? state.note).map(Value.string) ?? .null),
        ]
    }

    func setLoginItem(_ on: Bool) {
        loginItem.setEnabled(on)
        setShell(loginItemFields())
    }

    func refreshLoginItem() {
        let fields = loginItemFields()
        guard fields.contains(where: { shell[$0.0] != $0.1 }) else { return }
        setShell(fields)
    }

    private func refreshScreens() {
        let current = currentScreens()
        guard !current.isEmpty else { return }
        host.screens = current
    }

    func watch() {
        guard let location else { return }
        let themeFolders = themes.folders.filter { $0 == paths.themesDirectory || FileManager.default.fileExists(atPath: $0.path) }
        let wanted = Array(Set(([location.root.path, paths.userConfig.path, paths.stateDirectory.path] + themeFolders.map(\.path) + watchedFiles.map { $0.deletingLastPathComponent().path })
            .map(FolderWatcher.existingAncestor))).sorted()
        guard wanted != watchedPaths || watcher == nil else { return }
        watchedPaths = wanted
        watcher?.stop()
        let watcher = FolderWatcher { [weak self] paths in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.filesChanged(paths) } }
        }
        watcher.watch(wanted)
        self.watcher = watcher
    }

    func filesChanged(_ all: [String]) {
        if all.contains(where: themes.covers) { themes.invalidate() }
        let roots = ([location?.root, paths.userConfig, paths.stateDirectory].compactMap { $0 } + themes.folders + watchedFiles.map { $0.deletingLastPathComponent() }).map { Self.comparable($0.path) + "/" }
        let changed = all.filter { path in
            let candidate = Self.comparable(path) + "/"
            return roots.contains { candidate.hasPrefix($0) }
        }
        guard !changed.isEmpty else { return }
        let state = Self.comparable(paths.stateDirectory.path) + "/"
        let onlyState = changed.allSatisfy { Self.comparable($0).hasPrefix(state) }
        if onlyState {
            stateChanged()
        } else {
            debouncer.poke()
        }
    }

    static func comparable(_ path: String) -> String {
        let standard = URL(fileURLWithPath: path).standardizedFileURL.path
        for prefix in ["/private/var/", "/private/tmp/", "/private/etc/"] where standard.hasPrefix(prefix) {
            return String(standard.dropFirst("/private".count))
        }
        return standard
    }

    func stateChanged() {
        guard let location, let assembly, let writer = writers[location.id],
              let text = try? String(contentsOf: stateFile(location), encoding: .utf8),
              text != writer.lastWrittenText else { return }
        assembly.vars.applyExternal(text: text)
    }

    @discardableResult
    func reload() -> Task<Void, Never>? {
        guard let (location, notes) = activeLocationForReload() else { return nil }
        reloadGeneration += 1
        let generation = reloadGeneration
        let task = Task { @MainActor in
            var result = await load(location)
            guard generation == reloadGeneration else {
                await latestReload?.value
                return
            }
            result = ConfigLoadResult(ir: result.ir, diagnostics: notes + result.diagnostics, files: result.files)
            if result.ir != nil, Self.shellFileIsEmpty(location) {
                Self.log("shell.kdl of \(location.id) is empty, keeping the last config")
                return
            }
            if result.ir != nil {
                self.location = location
                watchedFiles = result.files
            }
            reloading = true
            applyFirstWeekday(result.ir)
            if assembly?.runtime.applyLoaded(result, persisted: persisted(for: location, ir: result.ir), screens: Self.screenOrder(host.screens), shell: shell, writer: writer(for: location)) == true {
                reloadsApplied += 1
            }
            reloading = false
            watch()
        }
        latestReload = task
        return task
    }

    static func shellFileIsEmpty(_ location: ConfigLocation) -> Bool {
        let file = location.root.appendingPathComponent("shell.kdl")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func activeLocationForReload() -> (ConfigLocation, [Diagnostic])? {
        guard let location else { return nil }
        _ = settings.reload()
        let (resolved, notes) = resolveActive()
        return (resolved, legacyNotes + notes)
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
        if let lastIR { applyCommandCenterVisibility(lastIR) }
        let control = LiveShellControl(shell: self)
        let server = ControlSocketServer(path: socketPath, service: ControlRouter(shell: control, configs: catalog, themes: ThemeCatalog(paths: paths, settings: settings)))
        do {
            try server.start()
            socket = server
        } catch {
            Self.log("control socket failed: \(error)")
        }
        let controller = UpdateController(settings: settings, machine: machine)
        updates = controller
        controller.onChange = { [weak self] in
            guard let self else { return }
            setShell([("update", updateField())])
        }
        setShell([("update", updateField())])
        fullscreen.observe()
        reservesChanged()
        installTermination()
        observeEnvironment()
    }

    func installTermination(signals: [Int32] = [SIGTERM, SIGINT], center: NotificationCenter = .default) {
        termination = TerminationWatch(signals: signals, center: center) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutdown() }
        }
    }

    func observeEnvironment() {
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.appearanceChanged() } }
        }
        let distributed = DistributedNotificationCenter.default()
        environmentObservers.append((distributed, distributed.addObserver(forName: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keyboardLayoutChanged() }
        }))
        let workspace = NSWorkspace.shared.notificationCenter
        environmentObservers.append((workspace, workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.accessibilityChanged() }
        }))
        environmentObservers.append((workspace, workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hotKeys?.retryFailed() }
        }))
        for (name, event) in [(NSWorkspace.willSleepNotification, "system.will-sleep"), (NSWorkspace.didWakeNotification, "system.did-wake"),
                              (NSWorkspace.sessionDidResignActiveNotification, "system.session-inactive"), (NSWorkspace.sessionDidBecomeActiveNotification, "system.session-active")] {
            environmentObservers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.assembly?.runtime.emit(event, Record()) }
            }))
        }
        environmentObservers.append((workspace, workspace.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == "com.apple.systempreferences" else { return }
            MainActor.assumeIsolated { self?.refreshLoginItem() }
        }))
    }

    func appearanceChanged() {
        let dark = isDark()
        guard dark != lastDark, host.context != nil else { return }
        host.restyle(makeContext(lastIR))
    }

    func recording(_ on: Bool) {
        recordings = max(0, recordings + (on ? 1 : -1))
        hotKeys?.suspended = recordings > 0
    }

    func accessibilityChanged() {
        guard host.context != nil, host.context?.styles.environment.reduceTransparency != accessibility().reduceTransparency
            || host.context?.styles.environment.reduceMotion != accessibility().reduceMotion else { return }
        host.restyle(makeContext(lastIR))
    }

    func keyboardLayoutChanged() {
        assembly?.bindings.invalidateAll()
    }

    func showOSD(_ id: String) {
        guard let runtime = assembly?.runtime else { return }
        let shown = host.shownKeys(id)
        runtime.open(id, screenKey: nil)
        host.restartTimeout(id, keys: shown)
    }

    func restart() {
        shutdown()
        relaunch(Bundle.main.bundleURL, ProcessInfo.processInfo.processIdentifier)
        terminateApp()
    }

    static func relaunchAfterExit(_ bundle: URL, _ pid: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; /usr/bin/open -n \"$0\"", bundle.path]
        try? process.run()
    }

    func commandCenterEntries() -> [MenuEntry] {
        let active = location?.id
        let themes = ThemeCatalog(paths: paths, settings: settings).list()
        var state = CommandCenterState(configs: catalog.list().map { .init(id: $0.id, isActive: $0.id == active) },
                                       themes: themes.map { .init(id: $0.id, issueCount: $0.issueCount, isActive: $0.isActive) })
        state.problemCount = overlay.problems.count
        state.marketplaceEnabled = marketplaceEnabled
        if let updates {
            state.update = updates.status
            state.lastUpdateCheck = updates.lastCheck
            state.releaseNotes = updates.releaseNotes
            state.installKind = updates.installKind
        }
        state.autoCheck = settings.settings.autoCheckUpdates
        state.autoInstall = settings.settings.autoInstallUpdates
        state.crashReports = settings.crashReportMode
        state.startsAtLogin = loginItem.state.isOn
        state.cliInstalled = commandLineTool.isInstalled
        commandCenterHandlers.removeAll()
        let spec = lastIR?.commandCenter?.items.map { CommandCenterSpec(entries: commandCenterSpecEntries($0, locals: [:])) }
        return CommandCenterModel.build(spec, state: state)
    }

    func commandCenterSpecEntries(_ items: [MenuItemIR], locals: [String: Value]) -> [CommandCenterEntry] {
        guard let runtime = assembly?.runtime else { return [] }
        func value(_ compiled: CompiledValue) -> Value { runtime.evaluate(compiled, locals: locals) }
        var result: [CommandCenterEntry] = []
        for item in items {
            switch item {
            case .builtin(let name):
                result.append(.builtin(name))
            case .separator:
                result.append(.separator)
            case let .item(title, properties, actions):
                let handler = "item-\(commandCenterHandlers.count + 1)"
                commandCenterHandlers[handler] = (actions, locals)
                result.append(.item(MenuItemSpec(
                    title: value(title).stringified,
                    icon: properties["icon"].map(value)?.plainText,
                    shortcut: properties["shortcut"].map(value)?.plainText,
                    checked: properties["checked"].map(value)?.isTruthy ?? false,
                    disabled: properties["disabled"].map(value)?.isTruthy ?? false,
                    handler: handler
                )))
            case let .submenu(title, children):
                result.append(.submenu(title: value(title).stringified, entries: commandCenterSpecEntries(children, locals: locals)))
            case let .each(variable, index, list, _, body):
                guard case .list(let values) = value(list) else { continue }
                for (offset, entry) in values.enumerated() {
                    var inner = locals
                    inner[variable] = entry
                    if let index { inner[index] = .number(Double(offset)) }
                    result += commandCenterSpecEntries(body, locals: inner)
                }
            case let .when(condition, then, otherwise):
                result += commandCenterSpecEntries(value(condition).isTruthy ? then : otherwise, locals: locals)
            case .section, .source:
                continue
            }
        }
        return result
    }

    func applyCommandCenterVisibility(_ ir: ConfigIR) {
        guard let commandCenter else { return }
        commandCenter.visible = ir.commandCenter?.visible.map { assembly?.runtime.evaluate($0, locals: [:]).isTruthy ?? true } ?? true
    }

    var commandLineTool: CommandLineToolInstaller {
        CommandLineToolInstaller(home: home, helper: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/apollo"))
    }

    func notice(_ title: String, _ body: String? = nil, kind: String = "info") {
        var fields: [(String, Value)] = [("title", .string(title)), ("kind", .string(kind))]
        if let body { fields.append(("body", .string(body))) }
        if toasts.post(style: "default", fields: Record(fields), duration: nil) == nil {
            overlay.add(Diagnostic(kind == "error" ? .warning : .note, body.map { "\(title): \($0)" } ?? title))
        }
    }

    func copyToOwnConfig() {
        guard let location else { return }
        let base = location.id.hasSuffix("-copy") ? location.id : location.id + "-copy"
        let taken = Set(catalog.list().map(\.id))
        var id = base
        var number = 2
        while taken.contains(id) {
            id = "\(base)-\(number)"
            number += 1
        }
        do {
            try catalog.fork(location.id, as: id)
            reload()
            if let root = paths.configRoot(for: id) { openFolder(root) }
        } catch {
            overlay.add(Diagnostic(.warning, "\(error)"))
        }
    }

    var openFolder: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
    var loginShellPath: @MainActor (String) -> String? = { LiveShell.loginShellPath($0) }

    func showThemeIssues(_ id: String) {
        for folder in [paths.themesDirectory, paths.legacyThemesDirectory] {
            guard let theme = ThemeLoader.themes(in: folder).first(where: { $0.identifier == id }) else { continue }
            overlay.show(theme.issues.map { Diagnostic(.warning, "theme \(id): \($0)") })
            return
        }
    }

    func addTheme() {
        let panel = NSOpenPanel()
        panel.title = "Add Theme"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "css") ?? .data, .folder]
        NSApp.activate()
        guard panel.runModal() == .OK, let source = panel.url else { return }
        addTheme(from: source)
    }

    func addTheme(from source: URL) {
        let target = paths.themesDirectory.appendingPathComponent(source.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: paths.themesDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            overlay.add(Diagnostic(.warning, "could not add the theme \(source.lastPathComponent): \(error.localizedDescription)"))
            return
        }
        let catalog = ThemeCatalog(paths: paths, settings: settings)
        let added = ThemeLoader.themes(in: paths.themesDirectory).first { theme in
            theme.identifier == source.deletingPathExtension().lastPathComponent || theme.identifier == source.lastPathComponent
        }
        guard let added else {
            overlay.add(Diagnostic(.warning, "\(source.lastPathComponent) is not a theme (a .css file or a folder with theme.css)"))
            return
        }
        do { try catalog.select(added.identifier); reload() } catch { overlay.add(Diagnostic(.warning, "\(error)")) }
    }

    func installCommandLineTool() {
        let tool = commandLineTool
        do {
            try tool.install()
        } catch {
            notice("Command line tool not installed", "\(error)", kind: "error")
            return
        }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let hint = CommandLineToolInstaller.pathHint(path: loginShellPath(shell) ?? "", shell: shell, home: tool.home)
        notice("apollo installed in ~/.local/bin", hint, kind: "success")
    }

    static func loginShellPath(_ shell: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "echo $PATH"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline { usleep(20_000) }
        if process.isRunning { process.terminate(); return nil }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: ":")
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
        case .openMarketplace: openMarketplace()
        case .checkForUpdates: updates?.checkNow()
        case .about:
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        case .quit:
            shutdown()
            terminateApp()
        case .restart:
            restart()
        case .copyToOwnConfig: copyToOwnConfig()
        case .showThemeIssues(let id): showThemeIssues(id)
        case .addTheme: addTheme()
        case .installUpdate: updates?.installNowIfReady()
        case .releaseNotes(let url): NSWorkspace.shared.open(url)
        case .setAutoCheck(let on):
            do { try settings.apply(.updates(autoCheck: on, autoInstall: settings.settings.autoInstallUpdates)) } catch { overlay.add(Diagnostic(.warning, "\(error)")) }
        case .setAutoInstall(let on):
            do { try settings.apply(.updates(autoCheck: settings.settings.autoCheckUpdates, autoInstall: on)) } catch { overlay.add(Diagnostic(.warning, "\(error)")) }
        case .copyBrewUpgrade:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(InstallKind.homebrewUpgradeCommand, forType: .string)
        case .crashReports(let mode):
            do { try settings.apply(.crashReports(mode.rawValue)) } catch { overlay.add(Diagnostic(.warning, "\(error)")) }
        case .setStartAtLogin(let on): setLoginItem(on)
        case .installCommandLineTool: installCommandLineTool()
        case .custom(let name):
            if let handler = commandCenterHandlers[name] {
                _ = assembly?.actions.trigger(handler.actions, site: "command-center#\(name)", environment: ActionEnvironment(scope: LocalScope(handler.locals)))
            } else {
                _ = assembly?.runtime.emit("command-center." + name, Record())
            }
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

    static func imageData(_ providers: [any ProviderInstance]) -> @MainActor (ImageRef) -> Data? {
        let media = providers.compactMap { $0 as? MediaProvider }.first
        let system = providers.compactMap { $0 as? SystemProvider }.first
        return { ref in
            switch ref.source {
            case "media": media?.artworkData(ref.id)
            case "user-image": system?.userImageData(ref.id)
            default: nil
            }
        }
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

    func close(_ surfaceID: String, screenKey: String) {
        assembly?.runtime.close(surfaceID, screenKey: screenKey)
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
        guard shutdowns == 0 else { return }
        shutdowns += 1
        toasts.stop()
        termination?.cancel()
        appearanceObservation = nil
        for (center, observer) in environmentObservers { center.removeObserver(observer) }
        environmentObservers.removeAll()
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
                ("styles-computed", .number(Double(StyleResolver.computedTotal))),
                ("longest-block-ms", .number(MainBlockObserver.shared.takeLongest())),
            ]))
        }
    }

    func quit() async {
        await MainActor.run {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak shell] in
                MainActor.assumeIsolated {
                    shell?.shutdown()
                    shell?.terminateApp()
                }
            }
        }
    }

    func restart() async {
        await MainActor.run {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak shell] in
                MainActor.assumeIsolated { shell?.restart() }
            }
        }
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
