import Testing
import AppKit
import ApolloBase
import ApolloConfig
import ApolloRuntime
import ApolloStyle
import ApolloShellCore
@testable import ApolloShell

@MainActor
enum TestPNG {
    static func data(_ size: Int = 4) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.setColor(.red, atX: 0, y: 0)
        return rep.representation(using: .png, properties: [:])!
    }
}

@MainActor
@Suite("Live-Verdrahtung des Render-Kontexts")
struct LiveWiringTests {
    static func themed() throws -> ShellHarness {
        let harness = try ShellHarness("panel \"bar\" { row { text \"a\" } }", settings: "theme \"nacht\"\n")
        let folder = harness.home.appendingPathComponent("apolloshell/themes/nacht")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("icons"), withIntermediateDirectories: true)
        try ":root {\n  --apollo-theme-format: 1;\n  --apollo-theme-name: \"Nacht\";\n  --apollo-theme-appearance: dark;\n}\n"
            .write(to: folder.appendingPathComponent("theme.css"), atomically: true, encoding: .utf8)
        try TestPNG.data().write(to: folder.appendingPathComponent("icons/bar-power.png"))
        harness.shell.isDark = { false }
        harness.shell.accessibility = { LiveAccessibility(reduceMotion: true, reduceTransparency: true) }
        return harness
    }

    @Test("connectLive, Umgebung aus Systemeinstellung und aktivem Theme, Wurzeln")
    func context() async throws {
        let harness = try Self.themed()
        try await harness.start()
        let context = try #require(harness.shell.host.context)
        #expect(context.runtime != nil)
        #expect(!context.menuSources.isEmpty)
        #expect(context.styles.environment.reduceTransparency)
        #expect(context.styles.environment.reduceMotion)
        #expect(context.styles.environment.appearance == .dark)
        #expect(context.configRoot?.standardizedFileURL.path == harness.config.standardizedFileURL.path)
        #expect(context.styles.assetRoot?.standardizedFileURL.path == harness.config.standardizedFileURL.path)
        #expect(context.theme("nacht")?.identifier == "nacht")
        #expect(context.theme("default") == .standard)
        #expect(context.theme("fehlt") == nil)
    }

    @Test("Theme-Symbole kommen aus dem aktiven Theme und werden nur einmal gelesen")
    func themeIcons() async throws {
        let harness = try Self.themed()
        try await harness.start()
        let context = try #require(harness.shell.host.context)
        #expect(context.themeIcon("bar-power") != nil)
        #expect(context.themeIcon("bar-power") != nil)
        #expect(context.themeIcon("bar-clock") == nil)
        #expect(context.themeIcon("bar-clock") == nil)
        #expect(harness.shell.themes.diskReads == 1)
    }

    @Test("Provider-Bilder wie media.artwork kommen über imageValue")
    func providerImages() async throws {
        let harness = try ShellHarness("panel \"bar\" { row { text \"a\" } }")
        try await harness.start()
        var asked: [ImageRef] = []
        harness.shell.providerImages.data = { ref in
            asked.append(ref)
            return ref.source == "media" ? TestPNG.data() : nil
        }
        let context = try #require(harness.shell.host.context)
        let artwork = Value.image(ImageRef(source: "media", id: "artwork-1-1"))
        #expect(context.image(for: artwork) != nil)
        #expect(context.image(for: artwork) != nil)
        #expect(context.image(for: .image(ImageRef(source: "user-image", id: "x"))) == nil)
        #expect(asked.count == 2)
    }
}
