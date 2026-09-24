import Foundation
import Testing
@testable import ApolloShellCore

@Suite("App-Suche auf der Platte")
struct AppCatalogTests {
    /// Legt ein falsches .app-Bundle mit Info.plist an.
    private func makeApp(_ path: String, in root: URL, bundleID: String) throws {
        let contents = root.appendingPathComponent(path).appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    private func tempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("launcher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("findet Apps direkt und eine Ordnerebene tiefer, alphabetisch")
    func findsTopLevelAndNested() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApp("Zed.app", in: root, bundleID: "dev.zed")
        try makeApp("Blender.app", in: root, bundleID: "org.blender")
        try makeApp("Adobe Illustrator 2026/Adobe Illustrator.app", in: root, bundleID: "com.adobe.illustrator")

        let names = AppCatalog(roots: [root]).scan().map(\.name)
        #expect(names == ["Adobe Illustrator", "Blender", "Zed"])
    }

    @Test("sucht nicht in .app-Bundles hinein")
    func skipsHelpersInsideBundles() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApp("Main.app", in: root, bundleID: "com.example.main")
        try makeApp("Main.app/Contents/Helpers/Helper.app", in: root, bundleID: "com.example.helper")

        let names = AppCatalog(roots: [root]).scan().map(\.name)
        #expect(names == ["Main"])
    }

    @Test("geht nicht tiefer als erlaubt")
    func respectsMaxDepth() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApp("a/b/Deep.app", in: root, bundleID: "com.example.deep")

        #expect(AppCatalog(roots: [root], maxDepth: 2).scan().isEmpty)
        #expect(AppCatalog(roots: [root], maxDepth: 3).scan().map(\.name) == ["Deep"])
    }

    @Test("gleiche Bundle-ID in zwei Ordnern erscheint nur einmal")
    func deduplicatesByBundleID() throws {
        let first = try tempRoot()
        let second = try tempRoot()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        try makeApp("Tool.app", in: first, bundleID: "com.example.tool")
        try makeApp("Tool.app", in: second, bundleID: "com.example.tool")

        #expect(AppCatalog(roots: [first, second]).scan().count == 1)
    }

    @Test("fehlender Ordner ist kein Fehler")
    func missingRootIsEmpty() {
        let missing = URL(fileURLWithPath: "/gibt/es/nicht-\(UUID().uuidString)")
        #expect(AppCatalog(roots: [missing]).scan().isEmpty)
    }
}
