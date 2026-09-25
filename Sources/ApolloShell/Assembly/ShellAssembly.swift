import Foundation
import ApolloBase
import ApolloConfig
import ApolloRuntime
import ApolloProviders
import ApolloShellCore

@MainActor
final class ShellAssembly {
    let scheduler: any FlushScheduler
    let store: SignalStore
    let bindings: BindingEngine
    let vars: VarStore
    let providers: ProviderHost
    let actions: ActionDispatcher
    let runtime: ShellRuntime
    private(set) var warnings: [Diagnostic] = []
    var onWarning: (@MainActor (Diagnostic) -> Void)?

    init(host: any SurfaceHosting, scheduler: any FlushScheduler, clock: any RuntimeClock = DispatchRuntimeClock(), filterContext: @escaping @Sendable () -> FilterContext) {
        self.scheduler = scheduler
        let evaluator = Evaluator(filters: .builtin, context: filterContext, warn: { _ in })
        store = SignalStore(scheduler: scheduler)
        bindings = BindingEngine(store: store, evaluator: evaluator)
        vars = VarStore(store: store, bindings: bindings, clock: clock)
        providers = ProviderHost(store: store)
        actions = ActionDispatcher(evaluator: evaluator, vars: vars, providers: providers, store: store, clock: clock)
        runtime = ShellRuntime(registry: .builtin, evaluator: evaluator, store: store, bindings: bindings, vars: vars, providers: providers, actions: actions, host: host)
        runtime.onWarning = { [weak self] in self?.warned($0) }
        actions.onWarning = { [weak self] in self?.warned($0) }
        vars.onWarning = { [weak self] in self?.warned($0) }
        providers.onWarning = { [weak self] in self?.warned($0) }
    }

    private func warned(_ diagnostic: Diagnostic) {
        warnings.append(diagnostic)
        onWarning?(diagnostic)
    }

    func install(_ list: [any ProviderInstance]) {
        for provider in list {
            providers.register(provider)
        }
    }

    func apply(_ ir: ConfigIR, screens: [String], shell: Record = Record()) {
        runtime.apply(ir, persisted: [:], screens: screens, shell: shell)
    }

    static func fixedContext(now: Date) -> @Sendable () -> FilterContext {
        let context = FilterContext(
            now: now,
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(identifier: "Europe/Zurich") ?? .current,
            services: DefaultFilterServices()
        )
        return { context }
    }
}

enum ConfigSource {
    static func load(_ folder: URL, builtinConfigs: URL, id: String) -> ConfigLoadResult {
        let paths = ConfigPaths(builtinConfigs: builtinConfigs, userConfig: folder, applicationSupport: FileManager.default.temporaryDirectory)
        let loader = ConfigLoader(fileSystem: DiskFileSystem(), paths: paths, registry: .builtin, filters: .builtin, shellVersion: ShellVersion.current)
        return loader.load(ConfigLocation(id: id, root: folder, isBuiltin: false))
    }
}
