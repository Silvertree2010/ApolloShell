import Testing
import AppKit
import ApolloShellCore
@testable import ApolloShell

@MainActor
@Suite("Theme-Symbole nur aus dem eigenen Theme-Ordner (N-2)")
struct ThemeRootTests {
    static func theme(_ folder: URL, icons: [String]) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: folder.appendingPathComponent("icons"), withIntermediateDirectories: true)
        try ":root {\n  --apollo-theme-format: 1;\n  --apollo-theme-name: \"T\";\n}\n"
            .write(to: folder.appendingPathComponent("theme.css"), atomically: true, encoding: .utf8)
        for icon in icons { try TestPNG.data().write(to: folder.appendingPathComponent("icons/\(icon).png")) }
    }

    static func scratch() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("theme-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @Test("Nach dem Laden auf ein Nachbar-Theme getauschter Symlink liefert nil")
    func neighbourSymlink() throws {
        let base = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: base) }
        let themes = base.appendingPathComponent("themes")
        try Self.theme(themes.appendingPathComponent("a"), icons: ["bar-power", "bar-clock"])
        try Self.theme(themes.appendingPathComponent("b"), icons: ["bar-power"])
        let live = LiveThemes(folders: [themes])
        live.reload(activeID: "a")
        let power = themes.appendingPathComponent("a/icons/bar-power.png")
        try FileManager.default.removeItem(at: power)
        try FileManager.default.createSymbolicLink(atPath: power.path, withDestinationPath: "../../b/icons/bar-power.png")
        #expect(live.icon("bar-clock") != nil)
        #expect(live.icon("bar-power") == nil)
    }

    @Test("Ein Theme-Ordner, der selbst ein Symlink ist, lädt seine Symbole")
    func symlinkedThemeFolder() throws {
        let base = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: base) }
        let themes = base.appendingPathComponent("themes")
        try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
        try Self.theme(base.appendingPathComponent("dev/nacht"), icons: ["bar-power"])
        try FileManager.default.createSymbolicLink(at: themes.appendingPathComponent("nacht"), withDestinationURL: base.appendingPathComponent("dev/nacht"))
        let live = LiveThemes(folders: [themes])
        live.reload(activeID: "nacht")
        #expect(live.active?.identifier == "nacht")
        #expect(live.icon("bar-power") != nil)
    }
}
