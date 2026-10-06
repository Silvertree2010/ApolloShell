import Testing
import AppKit
import ApolloConfig
@testable import ApolloShell

@MainActor
@Suite("image-Pfade relativ zur deklarierenden Datei")
struct ImagePathTests {
    func png(_ url: URL) throws {
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    @Test("ein eingebundenes image findet die Datei neben seiner kdl-Datei, sonst gilt die Config-Wurzel")
    func includedFile() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("img-\(UUID().uuidString)")
        let root = base.appendingPathComponent("cfg"), lib = base.appendingPathComponent("lib")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try png(lib.appendingPathComponent("bt.png"))
        try png(root.appendingPathComponent("top.png"))
        let ctx = RenderContext(styles: StyleResolver(sheets: [], environment: StyleSheets.environment(dark: false)), icons: FixtureAppIcons(), trigger: { _, _, _ in })
        ctx.configRoot = root
        let from = lib.appendingPathComponent("part.kdl").path
        #expect(ctx.image(for: .string("bt.png"), from: from) != nil)
        #expect(ctx.image(for: .string("bt.png")) == nil)
        #expect(ctx.image(for: .string("top.png"), from: from) != nil)
        #expect(ctx.image(for: .string("../cfg/top.png"), from: from) == nil)
    }
}
