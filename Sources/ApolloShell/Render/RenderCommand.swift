import AppKit
import SwiftUI
import ApolloBase
import ApolloConfig
import ApolloRuntime
import ApolloProviders

@MainActor
enum RenderCommand {
    static let usage = "usage: ApolloShell --render <folder> --fixture <file> [--config <folder>] [--resources <folder>] [--appearance light|dark] [--scale 2]"

    struct Options {
        var output: URL
        var fixture: URL
        var config: URL
        var resources: URL
        var dark: Bool
        var scale: CGFloat
    }

    static func options(_ arguments: [String], executable: URL) throws -> Options {
        func value(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        guard let output = value("--render"), let fixture = value("--fixture") else { throw RenderError.usage(usage) }
        let resources = value("--resources").map { URL(fileURLWithPath: $0) }
            ?? executable.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
        let config = value("--config").map { URL(fileURLWithPath: $0) } ?? resources.appendingPathComponent("render/dock")
        return Options(
            output: URL(fileURLWithPath: output, isDirectory: true),
            fixture: URL(fileURLWithPath: fixture),
            config: config.standardizedFileURL,
            resources: resources.standardizedFileURL,
            dark: value("--appearance") == "dark",
            scale: value("--scale").flatMap(Double.init).map { CGFloat($0) } ?? 2
        )
    }

    static func run(_ arguments: [String]) -> Int32 {
        do {
            let options = try options(arguments, executable: URL(fileURLWithPath: CommandLine.arguments[0]))
            try render(options)
            return 0
        } catch {
            FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
            return 1
        }
    }

    static func render(_ options: Options) throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.appearance = NSAppearance(named: options.dark ? .darkAqua : .aqua)
        var fixture = ProviderFixture.load(options.fixture)
        report(fixture.diagnostics)
        let extracted = FixtureIcons.extract(fixture.values)
        fixture.values = extracted.values
        var now = Date()
        if case .date(let date)? = fixture.values["clock"]?["now"] { now = date }
        let host = SurfaceHost()
        let scheduler = ManualFlushScheduler()
        let assembly = ShellAssembly(host: host, scheduler: scheduler, clock: ManualRuntimeClock(), filterContext: ShellAssembly.fixedContext(now: now))
        assembly.install(FixtureProvider.all(fixture: fixture, onAction: { action, _, _ in
            FileHandle.standardError.write(Data("action \(action) (not run)\n".utf8))
        }))
        let loaded = ConfigSource.load(options.config, builtinConfigs: options.resources.appendingPathComponent("configs"), id: "render")
        report(loaded.diagnostics)
        guard let ir = loaded.ir else { throw RenderError.config("config \(options.config.path) did not load") }
        assembly.apply(ir, screens: ["render"])
        for _ in 0..<50 { scheduler.runPending() }
        report(assembly.warnings)
        let (sheets, sheetDiagnostics) = StyleSheets.load(ir)
        report(sheetDiagnostics)
        let styles = StyleResolver(sheets: sheets, environment: StyleSheets.environment(dark: options.dark))
        let context = RenderContext(styles: styles, icons: FixtureAppIcons(files: extracted.icons, root: options.fixture.deletingLastPathComponent()), trigger: { _, _, _ in })
        let appearance: ColorScheme = options.dark ? .dark : .light
        let canvas = OffscreenCanvas(appearance: appearance, scale: options.scale)
        try FileManager.default.createDirectory(at: options.output, withIntermediateDirectories: true)
        for key in host.order {
            guard let surface = host.surfaces[key] else { continue }
            let name = "\(surface.id)-\(options.dark ? "dark" : "light").png"
            let view = SurfaceView(surface: surface, context: context)
                .environment(\.colorScheme, appearance)
                .environment(\._accessibilityReduceTransparency, true)
                .background(options.dark ? Color.black : Color.white)
                .transaction { transaction in
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            let hosting = NSHostingView(rootView: view)
            canvas.host(hosting, size: hosting.fittingSize)
            let data = try canvas.stableCapture(hosting, name: name)
            canvas.window.contentView = nil
            try data.write(to: options.output.appendingPathComponent(name))
        }
        report(styles.diagnostics)
    }

    static func report(_ diagnostics: [Diagnostic]) {
        for diagnostic in diagnostics {
            FileHandle.standardError.write(Data("\(diagnostic.severity): \(diagnostic.message)\n".utf8))
        }
    }
}
