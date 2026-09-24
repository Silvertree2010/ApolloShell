import Foundation
import Synchronization
import ApolloBase
import ApolloConfig
import ApolloRuntime

@MainActor
public enum FixtureFieldCheck {
    public static func run(_ ir: ConfigIR, fixture: ProviderFixture, registry: SchemaRegistry = .builtin, screens: [String] = ["main"]) -> [Diagnostic] {
        let sink = FieldCheckSink()
        let now = fixtureNow(fixture)
        let context = FilterContext(
            now: now,
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(identifier: "Europe/Zurich") ?? .current,
            services: DefaultFilterServices()
        )
        let evaluator = Evaluator(
            filters: .builtin,
            context: { context },
            warn: { sink.warning($0) },
            missingField: { path, span in sink.missing(path, span) }
        )
        let scheduler = ManualFlushScheduler()
        let store = SignalStore(scheduler: scheduler)
        let bindings = BindingEngine(store: store, evaluator: evaluator)
        let clock = ManualRuntimeClock()
        let vars = VarStore(store: store, bindings: bindings, clock: clock)
        let providers = ProviderHost(store: store)
        let actions = ActionDispatcher(evaluator: evaluator, vars: vars, providers: providers, store: store, clock: clock)
        let host = SilentHost()
        let runtime = ShellRuntime(registry: registry, evaluator: evaluator, store: store, bindings: bindings, vars: vars, providers: providers, actions: actions, host: host)
        runtime.onWarning = { sink.warning($0) }
        bindings.onWarning = { sink.warning($0) }
        for provider in FixtureProvider.all(fixture: fixture, registry: registry) {
            providers.register(provider)
        }
        let flush = {
            for _ in 0..<6 { scheduler.runPending() }
        }
        runtime.apply(ir, persisted: [:], screens: screens, shell: shellRecord(registry), writer: nil)
        flush()
        let variations = variations(ir)
        for surface in ir.surfaces {
            runtime.open(surface.id, screenKey: nil)
            flush()
            for (name, value) in variations {
                guard vars.set(name, value) else { continue }
                flush()
                vars.reset(name)
                flush()
            }
            runtime.close(surface.id)
            flush()
        }
        return sink.diagnostics
    }

    public static func variations(_ ir: ConfigIR) -> [(String, Value)] {
        let declared = Dictionary(ir.vars.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var found: [String: [Value]] = [:]
        func add(_ name: String, _ value: Value, strings: Bool = false) {
            guard let decl = declared[name], decl.derived == nil else { return }
            if strings, decl.type != .string { return }
            if !(found[name]?.contains(value) ?? false) { found[name, default: []].append(value) }
        }
        func bases(_ dependencies: Set<DependencyPath>, _ seen: Set<String> = []) -> Set<String> {
            var out: Set<String> = []
            for path in dependencies {
                let name = path.root == "var" ? path.fields.first : path.root
                guard let name, let decl = declared[name], !seen.contains(name) else { continue }
                if let derived = decl.derived {
                    out.formUnion(bases(derived.dependencies, seen.union([name])))
                } else {
                    out.insert(name)
                }
            }
            return out
        }
        func actionsIn(_ list: [ActionIR]) {
            for action in list {
                switch action {
                case .call(let call):
                    if call.name == "set", call.arguments.count >= 2,
                       case .string(let name)? = literal(call.arguments[0]), let value = literal(call.arguments[1]) {
                        add(name, value)
                    }
                case .when(_, let then, let otherwise):
                    actionsIn(then)
                    actionsIn(otherwise)
                case .switchOn(_, let cases, let otherwise):
                    cases.forEach { actionsIn($0.body) }
                    actionsIn(otherwise)
                case .each(_, _, _, let body), .repeatBlock(_, let body):
                    actionsIn(body)
                }
            }
        }
        func menuIn(_ items: [MenuItemIR]) {
            for item in items {
                switch item {
                case .item(_, _, let list): actionsIn(list)
                case .submenu(_, let inner), .each(_, _, _, _, let inner): menuIn(inner)
                case .when(_, let then, let otherwise):
                    menuIn(then)
                    menuIn(otherwise)
                default: break
                }
            }
        }
        func handlers(_ list: [HandlerIR], _ keys: [KeyHandlerIR]) {
            list.forEach { actionsIn($0.actions) }
            keys.forEach { actionsIn($0.actions) }
        }
        func children(_ list: [ChildIR]) {
            for child in list {
                switch child {
                case .element(let element):
                    handlers(element.handlers, element.keyHandlers)
                    element.accessibilityActions.forEach { actionsIn($0.actions) }
                    if let menu = element.menu { menuIn(menu.items) }
                    element.slots.values.forEach(children)
                    children(element.children)
                case .each(let each):
                    children(each.body)
                case .when(let when):
                    children(when.then)
                    children(when.otherwise)
                case .switchOn(let node):
                    let names = bases(node.subject.dependencies)
                    for item in node.cases {
                        for value in item.values.compactMap(literal) {
                            names.forEach { add($0, value, strings: true) }
                        }
                        children(item.body)
                    }
                    children(node.otherwise)
                case .dynamicUse(let use):
                    if case .parts(let parts) = use.name.template, parts.count == 2, case .text(let prefix) = parts[0] {
                        let names = bases(use.name.dependencies)
                        for define in ir.defines.keys.sorted() where define.hasPrefix(prefix) {
                            names.forEach { add($0, .string(String(define.dropFirst(prefix.count))), strings: true) }
                        }
                    }
                    use.slots.values.forEach(children)
                case .slot:
                    break
                }
            }
        }
        for surface in ir.surfaces {
            handlers(surface.handlers, surface.keyHandlers)
            children(surface.children)
        }
        for define in ir.defines.keys.sorted() {
            if let body = ir.defines[define]?.body { children(body) }
        }
        ir.binds.forEach { actionsIn($0.actions) }
        ir.events.forEach { actionsIn($0.actions) }
        for decl in ir.vars where decl.derived == nil {
            if case .scalar(let compiled) = decl.defaultValue, case .bool(let flag)? = literal(compiled) {
                add(decl.name, .bool(!flag))
            }
        }
        return ir.vars.flatMap { decl in (found[decl.name] ?? []).map { (decl.name, $0) } }
    }

    static func literal(_ value: CompiledValue) -> Value? {
        switch value.template {
        case .literal(let text): return .string(text)
        case .whole(.literal(let constant)): return constant
        default: return nil
        }
    }

    static func fixtureNow(_ fixture: ProviderFixture) -> Date {
        if case .date(let date)? = fixture.values["clock"]?["now"] { return date }
        return Date(timeIntervalSince1970: 1_790_236_800)
    }

    static func shellRecord(_ registry: SchemaRegistry) -> Record {
        var root = Value.record(Record())
        for field in registry.contextRoots["shell"]?.fields ?? [] {
            let path = field.path
            if ["configs", "themes", "hotkeys"].contains(path[0]) {
                root = FixtureProvider.insert(root, [path[0]], .list([]))
            } else if ProviderConformance.lookup(root, path) == nil {
                root = FixtureProvider.insert(root, path, field.type == .list ? .list([]) : .null)
            }
        }
        root = FixtureProvider.insert(root, ["fresh-install"], .bool(false))
        guard case .record(let record) = root else { return Record() }
        return record
    }
}

final class FieldCheckSink: Sendable {
    private let state = Mutex<(seen: Set<String>, diagnostics: [Diagnostic])>(([], []))

    func missing(_ path: String, _ span: SourceSpan?) {
        add(Diagnostic(.warning, "'\(path)' does not exist in the fixture record", span: span))
    }

    func warning(_ diagnostic: Diagnostic) {
        add(diagnostic)
    }

    private func add(_ diagnostic: Diagnostic) {
        let key = "\(diagnostic.message)|\(diagnostic.span.map { "\($0.file):\($0.start.line):\($0.start.column)" } ?? "")"
        state.withLock { state in
            guard !state.seen.contains(key) else { return }
            state.seen.insert(key)
            state.diagnostics.append(diagnostic)
        }
    }

    var diagnostics: [Diagnostic] {
        state.withLock { $0.diagnostics }
    }
}

@MainActor
final class SilentHost: SurfaceHosting {
    func surfaceAdded(_ surface: SurfaceInstance) {}
    func surfaceChanged(_ surface: SurfaceInstance) {}
    func surfaceReplaced(_ surface: SurfaceInstance) {}
    func surfaceRemoved(id: String, screenKey: String) {}
}
