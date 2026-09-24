import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Marketplace theme installer")
struct MarketThemeInstallerTests {
    static let css = ":root {\n  --apollo-theme-name: \"Dusk\";\n  --apollo-accent-color: #ff8a3d;\n}\n"

    static func theme(id: String = "t1", slug: String = "dusk", name: String = "Dusk", version: Int = 1, css: String = css) -> MarketTheme {
        MarketTheme(id: id, slug: slug, name: name, description: "", author: "octo", license: "CC0-1.0",
                    attribution: "", version: version, updatedAt: "", css: css)
    }

    struct Sandbox {
        let root: URL
        let installer: MarketThemeInstaller

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("market-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            installer = MarketThemeInstaller(
                themes: root.appendingPathComponent("config/themes"),
                legacyThemes: root.appendingPathComponent("support/themes"),
                indexFile: root.appendingPathComponent("support/marketplace.json")
            )
        }

        func prepareIndex(_ index: MarketInstallIndex) throws {
            try FileManager.default.createDirectory(at: installer.indexFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try index.save(to: installer.indexFile)
        }

        func text(_ name: String) throws -> String {
            try String(contentsOf: installer.themes.appendingPathComponent(name), encoding: .utf8)
        }

        func files(_ folder: URL) -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        }
    }

    @Test("unpacks a Marketplace answer into $CONFIG/themes/<slug>.css, readable as a theme")
    func unpacks() throws {
        let box = try Sandbox()
        let data = Data(#"{"id":"t1","slug":"dusk","name":"Dusk","description":"","author":"octo","license":"CC0-1.0","attribution":"","version":1,"updatedAt":"x","css":":root {\n  --apollo-theme-name: \"Dusk\";\n  --apollo-accent-color: #ff8a3d;\n}\n"}"#.utf8)
        let theme = try JSONDecoder().decode(MarketTheme.self, from: data)
        #expect(box.installer.state(of: theme) == .get)
        #expect(try box.installer.install(theme) == "dusk")
        #expect(box.files(box.installer.themes) == ["dusk.css"])
        let loaded = ThemeLoader.load(at: box.installer.themes.appendingPathComponent("dusk.css"))
        #expect(loaded.title == "Dusk")
        #expect(loaded.author == "octo")
        #expect(loaded.value(ThemeColorToken.accent) == ThemeColor(hex: 0xFF8A3D))
        #expect(box.installer.state(of: theme) == .use)
        #expect(box.installer.index().entries["t1"] == .init(fileName: "dusk.css", version: 1))
    }

    @Test("files get 0644, the folder 0755, nothing executable")
    func permissions() throws {
        let box = try Sandbox()
        try box.installer.install(Self.theme())
        let file = try FileManager.default.attributesOfItem(atPath: box.installer.themes.appendingPathComponent("dusk.css").path)
        let folder = try FileManager.default.attributesOfItem(atPath: box.installer.themes.path)
        #expect((file[.posixPermissions] as? NSNumber)?.intValue == 0o644)
        #expect((folder[.posixPermissions] as? NSNumber)?.intValue == 0o755)
    }

    @Test("an update overwrites its own file in place, a new theme dodges a taken name")
    func updateAndCollision() throws {
        let box = try Sandbox()
        try FileManager.default.createDirectory(at: box.installer.themes, withIntermediateDirectories: true)
        try "/* mine */".write(to: box.installer.themes.appendingPathComponent("dusk.css"), atomically: true, encoding: .utf8)
        #expect(try box.installer.install(Self.theme()) == "dusk-2")
        #expect(try box.text("dusk.css") == "/* mine */")
        #expect(box.installer.state(of: Self.theme(version: 2)) == .update)
        #expect(try box.installer.install(Self.theme(version: 2)) == "dusk-2")
        #expect(box.installer.index().entries["t1"]?.version == 2)
        #expect(box.files(box.installer.themes) == ["dusk-2.css", "dusk.css"])
        #expect(try box.installer.install(Self.theme(id: "t2")) == "dusk-3")
    }

    @Test("a theme installed by 0.1.4.2 in the old folder counts as installed and updates into $CONFIG")
    func legacyInstall() throws {
        let box = try Sandbox()
        try FileManager.default.createDirectory(at: box.installer.legacyThemes, withIntermediateDirectories: true)
        try Self.css.write(to: box.installer.legacyThemes.appendingPathComponent("Dusk.css"), atomically: true, encoding: .utf8)
        try box.prepareIndex(MarketInstallIndex(entries: ["t1": .init(fileName: "Dusk.css", version: 1)]))
        #expect(box.installer.state(of: Self.theme()) == .use)
        #expect(box.installer.state(of: Self.theme(version: 2)) == .update)
        #expect(try box.installer.install(Self.theme(version: 2)) == "Dusk")
        #expect(box.files(box.installer.themes) == ["Dusk.css"])
        #expect(try box.installer.remove("t1") == "Dusk")
        #expect(box.files(box.installer.themes).isEmpty)
        #expect(box.files(box.installer.legacyThemes).isEmpty)
        #expect(box.installer.index().entries.isEmpty)
    }

    @Test("broken entries are refused before anything is written", arguments: [
        (theme(id: ""), "badID"),
        (theme(id: "../x"), "badID"),
        (theme(slug: "../../etc/passwd"), "badSlug"),
        (theme(slug: "Dusk"), "badSlug"),
        (theme(slug: "dusk/.."), "badSlug"),
        (theme(slug: ""), "badSlug"),
        (theme(slug: "-dusk"), "badSlug"),
        (theme(version: 0), "badVersion"),
        (theme(css: String(repeating: " ", count: 70_000) + css), "tooLarge"),
        (theme(css: css + "\0"), "notText"),
        (theme(css: ":root {\n  --apollo-wallpaper: url(\"../../x.png\");\n}\n"), "usesFiles"),
        (theme(css: "@import url(\"https://evil.invalid/x.css\");\n" + css), "usesFiles"),
        (theme(css: "@import \"x.css\";\n" + css), "foreignRule"),
        (theme(css: ":root {\n  --not-apollo: 1;\n}\n"), "noTokens"),
        (theme(css: "garbage {{{"), "noTokens"),
    ])
    func refusesBroken(_ entry: (MarketTheme, String)) throws {
        let box = try Sandbox()
        do {
            try box.installer.install(entry.0)
            Issue.record("installed \(entry.0.slug)")
        } catch let problem as MarketInstallProblem {
            #expect(!problem.description.isEmpty)
            #expect(Self.kind(problem) == entry.1)
        }
        #expect(box.files(box.installer.themes).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: box.installer.indexFile.path))
        #expect(box.files(box.root).isEmpty)
    }

    static func kind(_ problem: MarketInstallProblem) -> String {
        switch problem {
        case .badID: "badID"
        case .badSlug: "badSlug"
        case .badVersion: "badVersion"
        case .tooLarge: "tooLarge"
        case .notText: "notText"
        case .usesFiles: "usesFiles"
        case .noTokens: "noTokens"
        case .foreignRule: "foreignRule"
        case .occupied: "occupied"
        case .notInstalled: "notInstalled"
        }
    }

    @Test("a tampered index cannot point outside the themes folder")
    func tamperedIndex() throws {
        let box = try Sandbox()
        let outside = box.root.appendingPathComponent("victim.css")
        try "keep".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: box.installer.indexFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try box.prepareIndex(MarketInstallIndex(entries: ["t1": .init(fileName: "../../victim.css", version: 1)]))
        #expect(box.installer.state(of: Self.theme()) == .get)
        #expect(try box.installer.install(Self.theme()) == "dusk")
        #expect(try String(contentsOf: outside, encoding: .utf8) == "keep")
        try box.prepareIndex(MarketInstallIndex(entries: ["t9": .init(fileName: "../../victim.css", version: 1)]))
        #expect(throws: MarketInstallProblem.notInstalled) { try box.installer.remove("t9") }
        #expect(try String(contentsOf: outside, encoding: .utf8) == "keep")
    }

    @Test("a symlink at the target is replaced, never written through")
    func symlinkTarget() throws {
        let box = try Sandbox()
        let outside = box.root.appendingPathComponent("victim.css")
        try "keep".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: box.installer.themes, withIntermediateDirectories: true)
        try box.prepareIndex(MarketInstallIndex(entries: ["t1": .init(fileName: "dusk.css", version: 1)]))
        try FileManager.default.createSymbolicLink(at: box.installer.themes.appendingPathComponent("dusk.css"), withDestinationURL: outside)
        try box.installer.install(Self.theme(version: 2))
        #expect(try String(contentsOf: outside, encoding: .utf8) == "keep")
        let type = try FileManager.default.attributesOfItem(atPath: box.installer.themes.appendingPathComponent("dusk.css").path)[.type] as? FileAttributeType
        #expect(type == .typeRegular)
    }

    @Test("a folder in the way is not overwritten")
    func folderInTheWay() throws {
        let box = try Sandbox()
        try FileManager.default.createDirectory(at: box.installer.themes.appendingPathComponent("dusk.css"), withIntermediateDirectories: true)
        try box.prepareIndex(MarketInstallIndex(entries: ["t1": .init(fileName: "dusk.css", version: 1)]))
        #expect(throws: MarketInstallProblem.occupied("dusk.css")) { try box.installer.install(Self.theme(version: 2)) }
    }

    @Test("a theme folder with the slug as name also blocks the slug")
    func themeFolderBlocks() throws {
        let box = try Sandbox()
        try FileManager.default.createDirectory(at: box.installer.legacyThemes.appendingPathComponent("dusk"), withIntermediateDirectories: true)
        #expect(try box.installer.install(Self.theme()) == "dusk-2")
    }
}
