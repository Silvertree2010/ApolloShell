import Testing
import Foundation
import AppKit
import ApolloConfig
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
}
