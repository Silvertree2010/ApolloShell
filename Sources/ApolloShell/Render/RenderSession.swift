import AppKit
import SwiftUI
import ApolloBase
import ApolloConfig
import ApolloRuntime
import ApolloProviders
import ApolloShellCore
import ApolloStyle

@MainActor
final class RenderSession {
    let host = SurfaceHost()
    let scheduler = ManualFlushScheduler()
    let assembly: ShellAssembly
    let context: RenderContext
    let canvas: OffscreenCanvas
    let dark: Bool
    let actionLog = ActionLog()
    var markRenderTime: TimeInterval = 0
    var actions: [String] { actionLog.entries }
    let renderVars: Record
    let renderToasts: [Value]

    init(config: URL, resources: URL, fixture: ProviderFixture, fixtureRoot: URL?, dark: Bool, scale: CGFloat, theme themeURL: URL? = nil,
         log: @escaping ([Diagnostic]) -> Void = { _ in }) throws {
        let theme = themeURL.map { ThemeLoader.load(at: $0) }
        let dark = theme.map { ThemeTokenBridge.effectiveAppearance(theme: $0, system: dark ? .dark : .light) == .dark } ?? dark
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        self.dark = dark
        var fixture = fixture
        renderVars = fixture.vars
        renderToasts = fixture.toasts
        let extracted = FixtureIcons.extract(fixture.values)
        fixture.values = extracted.values
        var now = Date()
        if case .date(let date)? = fixture.values["clock"]?["now"] { now = date }
        assembly = ShellAssembly(host: host, scheduler: scheduler, clock: ManualRuntimeClock(), filterContext: ShellAssembly.fixedContext(now: now))
        let actionLog = self.actionLog
        assembly.install(FixtureProvider.all(fixture: fixture, onAction: { action, _, _ in
            actionLog.entries.append(action)
            FileHandle.standardError.write(Data("action \(action) (not run)\n".utf8))
        }))
        let loaded = ConfigSource.load(config, builtinConfigs: resources.appendingPathComponent("configs"), id: "render")
        log(loaded.diagnostics)
        guard let ir = loaded.ir else { throw RenderError.config("config \(config.path) did not load") }
        let tokens = theme.map { ThemeTokenBridge.environment(for: $0, appearance: dark ? .dark : .light) } ?? .empty
        assembly.store.set(DependencyPath("theme", []), ThemeRoot.value(theme: theme, tokens: tokens, dark: dark))
        assembly.apply(ir, screens: ["render"], shell: fixture.shell)
        for _ in 0..<50 { scheduler.runPending() }
        log(assembly.warnings)
        let (sheets, sheetDiagnostics) = StyleSheets.load(ir)
        log(sheetDiagnostics)
        let styles = StyleResolver(sheets: sheets, environment: StyleSheets.environment(dark: dark, tokens: tokens), assetRoot: config)
        let assembly = assembly
        context = RenderContext(styles: styles, icons: FixtureAppIcons(files: extracted.icons, root: fixtureRoot), trigger: { name, identity, event in
            _ = assembly.runtime.trigger(name, on: identity, event: event)
        })
        context.configRoot = config
        context.keyName = { _ in nil }
        if let theme, let themeURL {
            let root = themeURL.hasDirectoryPath || themeURL.pathExtension.lowercased() != "css" ? themeURL : themeURL.deletingLastPathComponent()
            context.themeIcon = { id in theme.icons.file(id).flatMap { SafeImageFile.image(at: $0, root: root) } }
            context.theme = { name in name == theme.identifier ? theme : (name == "default" ? .standard : nil) }
        }
        context.runtime = AssemblyRenderRuntime(assembly)
        canvas = OffscreenCanvas(appearance: dark ? .dark : .light, scale: scale)
    }

    var surfaces: [SurfaceInstance] {
        host.order.compactMap { host.surfaces[$0] }
    }

    func surface(_ id: String) -> SurfaceInstance? {
        surfaces.first { $0.id == id }
    }

    func flush() {
        for _ in 0..<50 { scheduler.runPending() }
    }

    func mount(_ surface: SurfaceInstance) -> NSView {
        let hosting = NSHostingView(rootView: root(surface, reserve: EdgeInsets()))
        canvas.host(hosting, size: hosting.fittingSize)
        let key = SurfaceHost.key(surface.id, surface.screenKey)
        guard !FlyoutCollector.collect(surface.root).isEmpty else { return hosting }
        var reserved = EdgeInsets()
        for _ in 0..<10 {
            CFRunLoopRunInMode(.defaultMode, OffscreenCanvas.settleStep, false)
            hosting.layoutSubtreeIfNeeded()
            let wanted = context.flyoutExtents[key] ?? EdgeInsets()
            guard wanted != reserved else { continue }
            reserved = wanted
            hosting.rootView = root(surface, reserve: wanted)
            canvas.host(hosting, size: hosting.fittingSize)
        }
        return hosting
    }

    func root(_ surface: SurfaceInstance, reserve: EdgeInsets) -> AnyView {
        let appearance: ColorScheme = dark ? .dark : .light
        return AnyView(SurfaceView(surface: surface, context: context)
            .padding(reserve)
            .environment(\.colorScheme, appearance)
            .environment(\._accessibilityReduceTransparency, true)
            .environment(\.renderMode, true)
            .environment(\.markRenderTime, markRenderTime)
            .background(dark ? Color.black : Color.white)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            })
    }

    func capture(_ surface: SurfaceInstance, name: String) throws -> Data {
        var opened = Self.opensForCapture(surface)
        if surface.ir.kind == "toast", !surface.isOpen, !renderToasts.isEmpty {
            let records = renderToasts.enumerated().map { index, value -> Value in
                var record = Record([("id", .string("toast-\(index + 1)")), ("remaining", .number(5)), ("queued", .bool(false))])
                if case .record(let fields) = value { for key in fields.keys { record[key] = fields[key] } }
                if record["kind"] == nil { record["kind"] = .string("info") }
                return .record(record)
            }
            assembly.runtime.setToasts(surface.id, screenKey: surface.screenKey, records)
            opened = true
        }
        if opened {
            assembly.runtime.open(surface.id, screenKey: surface.screenKey)
            flush()
        }
        for name in renderVars.keys where assembly.actions.vars.isDeclared(name) {
            guard var value = renderVars[name] else { continue }
            if case .record(let record) = value, record.keys.isEmpty, case .list = assembly.actions.vars.value(name) { value = .list([]) }
            assembly.actions.vars.set(name, value)
        }
        if renderVars.count > 0 { flush() }
        let hosting = mount(surface)
        defer {
            canvas.window.contentView = nil
            if opened {
                assembly.runtime.close(surface.id)
                flush()
            }
        }
        return try canvas.stableCapture(hosting, name: name)
    }

    static func opensForCapture(_ surface: SurfaceInstance) -> Bool {
        !surface.isOpen && !["panel", "toast"].contains(surface.ir.kind)
    }
}

@MainActor
final class ActionLog {
    var entries: [String] = []
}

private struct RenderModeKey: EnvironmentKey {
    static let defaultValue = false
}

private struct MarkRenderTimeKey: EnvironmentKey {
    static let defaultValue: TimeInterval = 0
}

private struct SurfaceShownKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var surfaceShown: Bool {
        get { self[SurfaceShownKey.self] }
        set { self[SurfaceShownKey.self] = newValue }
    }

    var markRenderTime: TimeInterval {
        get { self[MarkRenderTimeKey.self] }
        set { self[MarkRenderTimeKey.self] = newValue }
    }

    var renderMode: Bool {
        get { self[RenderModeKey.self] }
        set { self[RenderModeKey.self] = newValue }
    }
}
