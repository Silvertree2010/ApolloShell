import Testing
import Foundation
import AppKit
import ApolloConfig
import ApolloStyle
@testable import ApolloShell

@MainActor
@Suite("Fixture-Symbole und sichere Bilddateien")
struct FixtureIconTests {
    func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-icons-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url.appendingPathComponent("icons"), withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.systemGreen.setFill()
            rect.fill()
            return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try rep.representation(using: .png, properties: [:])!.write(to: url.appendingPathComponent("icons/finder.png"))
        return url
    }

    @Test("icon= wird aus App-Records genommen und aus den Providerwerten entfernt")
    func extract() {
        let dock = Value.list([
            .record(Record([("bundle-id", .string("com.apple.finder")), ("icon", .string("icons/finder.png"))])),
            .record(Record([("bundle-id", .string("com.apple.mail"))])),
        ])
        let (values, icons) = FixtureIcons.extract(["apps": Record([("dock", dock)])])
        #expect(icons == ["com.apple.finder": "icons/finder.png"])
        guard case .list(let items)? = values["apps"]?["dock"], case .record(let first) = items[0] else {
            Issue.record("dock missing")
            return
        }
        #expect(first["icon"] == nil)
        #expect(first["bundle-id"] == .string("com.apple.finder"))
    }

    @Test("Symbol aus Datei, ohne Feld Farbfläche")
    func icons() throws {
        let root = try folder()
        let source = FixtureAppIcons(files: ["com.apple.finder": "icons/finder.png"], root: root)
        #expect(source.icon(for: .string("com.apple.finder"))?.size == NSSize(width: 4, height: 4))
        #expect(source.icon(for: .string("com.apple.mail"))?.size == NSSize(width: 64, height: 64))
    }

    @Test("Symlink aus dem Ordner hinaus, .. und absolute Pfade werden beim Lesen abgelehnt")
    func rejects() throws {
        let root = try folder()
        let outside = try folder()
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("icons/escape.png"),
                                                   withDestinationURL: outside.appendingPathComponent("icons/finder.png"))
        #expect(SafeImageFile.data("icons/finder.png", root: root) != nil)
        #expect(SafeImageFile.data("icons/escape.png", root: root) == nil)
        #expect(SafeImageFile.data("../x/icons/finder.png", root: root) == nil)
        #expect(SafeImageFile.data(outside.appendingPathComponent("icons/finder.png").path, root: root) == nil)
        #expect(SafeImageFile.data(at: outside.appendingPathComponent("icons/finder.png"), root: root) == nil)
    }

    @Test("Öffnen lehnt Symlinks in jeder Pfadkomponente ab, nicht nur in der letzten")
    func noSymlinkComponent() throws {
        let root = try folder()
        let real = try #require(SafeImageFile.realPath(root.path))
        try FileManager.default.createSymbolicLink(atPath: real + "/linked", withDestinationPath: real + "/icons")
        let direct = try #require(SafeImageFile.openRegular(real + "/icons/finder.png"))
        close(direct)
        let through = SafeImageFile.openRegular(real + "/linked/finder.png")
        through.map { _ = close($0) }
        #expect(through == nil)
    }

    @Test("url()-Bild gilt nur im Ordner des eigenen Stylesheets, nicht in einem anderen Sheet-Ordner")
    func boundToOwnSheet() throws {
        let own = try folder()
        let other = try folder()
        let (ownSheet, _) = StyleSheet.parse("", file: own.appendingPathComponent("a.css").path, origin: .config, assetRoot: own)
        let (otherSheet, _) = StyleSheet.parse("", file: other.appendingPathComponent("b.css").path, origin: .config, assetRoot: other)
        let resolver = StyleResolver(sheets: [ownSheet, otherSheet], environment: StyleSheets.environment(dark: false))
        let target = own.resolvingSymlinksInPath().appendingPathComponent("icons/finder.png")
        #expect(StyleResolver(sheets: [ownSheet, otherSheet], environment: StyleSheets.environment(dark: false)).image(target.path) != nil)
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: other.resolvingSymlinksInPath().appendingPathComponent("icons/finder.png"))
        #expect(resolver.image(target.path) == nil)
    }

    static func crc(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB8_8320 : 0) }
        }
        return ~crc
    }

    static func png(width: UInt32, height: UInt32) throws -> Data {
        func be(_ value: UInt32) -> [UInt8] { [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)] }
        func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
            let head = Array(type.utf8) + body
            return be(UInt32(body.count)) + head + be(crc(head))
        }
        let header = be(width) + be(height) + [1, 0, 0, 0, 0]
        let rows = Data(count: Int(height) * (Int(width + 7) / 8 + 1))
        let deflated = try (rows as NSData).compressed(using: .zlib) as Data
        let idat = [0x78, 0x9C] + [UInt8](deflated) + be(1)
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + chunk("IHDR", header) + chunk("IDAT", idat) + chunk("IEND", []))
    }

    @Test("Pixelmass wird vor dem Dekodieren begrenzt, kleine Datei mit riesiger Fläche fällt weg")
    func pixelLimit() throws {
        let root = try folder()
        let bomb = root.appendingPathComponent("icons/bomb.png")
        try Self.png(width: 12_000, height: 12_000).write(to: bomb)
        #expect(try Data(contentsOf: bomb).count < 64 * 1024)
        #expect(SafeImageFile.pixelCount(try Data(contentsOf: bomb)) == 144_000_000)
        #expect(SafeImageFile.image(at: bomb, root: root) == nil)
        #expect(SafeImageFile.image(at: root.appendingPathComponent("icons/finder.png"), root: root) != nil)
    }
}
