import Foundation
import Testing
@testable import ApolloShellCore

@Suite("The app search on the disk")
struct AppCatalogTests {
    /// Creates a fake .app bundle with an Info.plist.
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

    @Test("finds apps directly and one folder level deeper, alphabetically")
    func findsTopLevelAndNested() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApp("Zed.app", in: root, bundleID: "dev.zed")
        try makeApp("Blender.app", in: root, bundleID: "org.blender")
        try makeApp("Adobe Illustrator 2026/Adobe Illustrator.app", in: root, bundleID: "com.adobe.illustrator")

        let names = AppCatalog(roots: [root]).scan().map(\.name)
        #expect(names == ["Adobe Illustrator", "Blender", "Zed"])
    }

    @Test("does not search inside .app bundles")
    func skipsHelpersInsideBundles() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApp("Main.app", in: root, bundleID: "com.example.main")
        try makeApp("Main.app/Contents/Helpers/Helper.app", in: root, bundleID: "com.example.helper")

        let names = AppCatalog(roots: [root]).scan().map(\.name)
        #expect(names == ["Main"])
    }

    @Test("does not go deeper than allowed")
    func respectsMaxDepth() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeApp("a/b/Deep.app", in: root, bundleID: "com.example.deep")

        #expect(AppCatalog(roots: [root], maxDepth: 2).scan().isEmpty)
        #expect(AppCatalog(roots: [root], maxDepth: 3).scan().map(\.name) == ["Deep"])
    }

    @Test("the same bundle ID in two folders appears only once")
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

    @Test("a missing folder is no error")
    func missingRootIsEmpty() {
        let missing = URL(fileURLWithPath: "/does/not/exist-\(UUID().uuidString)")
        #expect(AppCatalog(roots: [missing]).scan().isEmpty)
    }

    @Test("Safari is found, although /Applications only has a hidden symlink to it")
    func findsSafari() throws {
        let cryptex = "/System/Cryptexes/App/System/Applications/Safari.app"
        try #require(FileManager.default.fileExists(atPath: cryptex), "this Mac has no Safari in the cryptex")
        #expect(AppCatalog().scan().contains { $0.bundleID == "com.apple.Safari" })
    }
}
