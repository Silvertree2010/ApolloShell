import AppKit
import SwiftUI
import ApolloBase
import ApolloConfig
import ApolloRuntime
import ApolloProviders

@MainActor
enum RenderCommand {
    static let usage = "usage: ApolloShell --render <folder> --fixture <file> [--config <folder>] [--resources <folder>] [--theme <file>] [--appearance light|dark] [--scale 2]"

    struct Options {
        var output: URL
        var fixture: URL
        var config: URL
        var resources: URL
        var dark: Bool
        var scale: CGFloat
        var theme: URL?
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
            scale: value("--scale").flatMap(Double.init).map { CGFloat($0) } ?? 2,
            theme: value("--theme").map { URL(fileURLWithPath: $0).standardizedFileURL }
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
        var fixture = ProviderFixture.load(options.fixture)
        report(fixture.diagnostics)
        let session = try RenderSession(config: options.config, resources: options.resources, fixture: fixture,
                                        fixtureRoot: options.fixture.deletingLastPathComponent(), dark: options.dark, scale: options.scale, theme: options.theme, log: report)
        fixture.values = [:]
        try FileManager.default.createDirectory(at: options.output, withIntermediateDirectories: true)
        for surface in session.surfaces {
            let name = "\(surface.id)-\(session.dark ? "dark" : "light").png"
            try session.capture(surface, name: name).write(to: options.output.appendingPathComponent(name))
        }
        report(session.context.styles.diagnostics)
    }

    static func report(_ diagnostics: [Diagnostic]) {
        for diagnostic in diagnostics {
            FileHandle.standardError.write(Data("\(diagnostic.severity): \(diagnostic.message)\n".utf8))
        }
    }
}
