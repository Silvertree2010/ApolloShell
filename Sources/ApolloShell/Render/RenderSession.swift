import AppKit
import SwiftUI
import ApolloBase
import ApolloConfig
import ApolloRuntime
import ApolloProviders

@MainActor
final class RenderSession {
    let host = SurfaceHost()
    let scheduler = ManualFlushScheduler()
    let assembly: ShellAssembly
    let context: RenderContext
    let canvas: OffscreenCanvas
    let dark: Bool
    var actions: [String] = []

    init(config: URL, resources: URL, fixture: ProviderFixture, fixtureRoot: URL?, dark: Bool, scale: CGFloat,
         log: @escaping ([Diagnostic]) -> Void = { _ in }) throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        self.dark = dark
        var fixture = fixture
        let extracted = FixtureIcons.extract(fixture.values)
        fixture.values = extracted.values
        var now = Date()
        if case .date(let date)? = fixture.values["clock"]?["now"] { now = date }
        assembly = ShellAssembly(host: host, scheduler: scheduler, clock: ManualRuntimeClock(), filterContext: ShellAssembly.fixedContext(now: now))
        var logged: [String] = []
        assembly.install(FixtureProvider.all(fixture: fixture, onAction: { action, _, _ in
            logged.append(action)
            FileHandle.standardError.write(Data("action \(action) (not run)\n".utf8))
        }))
        let loaded = ConfigSource.load(config, builtinConfigs: resources.appendingPathComponent("configs"), id: "render")
        log(loaded.diagnostics)
        guard let ir = loaded.ir else { throw RenderError.config("config \(config.path) did not load") }
        assembly.apply(ir, screens: ["render"])
        for _ in 0..<50 { scheduler.runPending() }
        log(assembly.warnings)
        let (sheets, sheetDiagnostics) = StyleSheets.load(ir)
        log(sheetDiagnostics)
        let styles = StyleResolver(sheets: sheets, environment: StyleSheets.environment(dark: dark), assetRoot: config)
        let assembly = assembly
        context = RenderContext(styles: styles, icons: FixtureAppIcons(files: extracted.icons, root: fixtureRoot), trigger: { name, identity, event in
            _ = assembly.runtime.trigger(name, on: identity, event: event)
        })
        context.configRoot = config
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

    func capture(_ surface: SurfaceInstance, name: String) throws -> Data {
        let appearance: ColorScheme = dark ? .dark : .light
        let view = SurfaceView(surface: surface, context: context)
            .environment(\.colorScheme, appearance)
            .environment(\._accessibilityReduceTransparency, true)
            .environment(\.renderMode, true)
            .background(dark ? Color.black : Color.white)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        let hosting = NSHostingView(rootView: view)
        canvas.host(hosting, size: hosting.fittingSize)
        defer { canvas.window.contentView = nil }
        return try canvas.stableCapture(hosting, name: name)
    }
}

private struct RenderModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var renderMode: Bool {
        get { self[RenderModeKey.self] }
        set { self[RenderModeKey.self] = newValue }
    }
}
