import ApolloShellCore
import Foundation
import Testing

@Suite("Themes: Symbole aus dem Theme")
struct ThemeIconsTests {
    /// Reicht als Datei - geprueft wird der Pfad, nicht der Bildinhalt.
    private let pixel = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    private func themeFolder(_ icons: [String], css: String = ":root { --apollo-theme-name: \"Icons\"; }") throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("apolloshell-icons-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("Icons")
        let iconsFolder = folder.appendingPathComponent(ThemeIconCatalog.folderName)
        try FileManager.default.createDirectory(at: iconsFolder, withIntermediateDirectories: true)
        try Data(css.utf8).write(to: folder.appendingPathComponent(ThemeLoader.styleSheetName))
        for name in icons {
            try pixel.write(to: iconsFolder.appendingPathComponent(name))
        }
        return folder
    }

    @Test("jede Kennung im Verzeichnis ist klein geschrieben und einmalig")
    func catalogIsClean() {
        var seen: Set<String> = []
        for icon in ThemeIconCatalog.standard.icons {
            #expect(icon.id == icon.id.lowercased(), "\(icon.id) ist nicht klein geschrieben")
            #expect(!icon.id.contains(" "), "\(icon.id) enthaelt ein Leerzeichen")
            #expect(seen.insert(icon.id).inserted, "\(icon.id) steht doppelt im Verzeichnis")
        }
    }

    @Test("ein Bild im Ordner ersetzt genau sein Symbol")
    func fileReplacesIcon() throws {
        let folder = try themeFolder(["session-shutdown.png"])
        let theme = ThemeLoader.load(at: folder)
        #expect(theme.icon("session-shutdown")?.lastPathComponent == "session-shutdown.png")
        #expect(theme.icon("session-restart") == nil, "was nicht dabei ist, bleibt das eingebaute Symbol")
    }

    @Test("Gross- und Kleinschreibung im Dateinamen ist egal")
    func caseDoesNotMatter() throws {
        let folder = try themeFolder(["Session-Shutdown.png"])
        #expect(ThemeLoader.load(at: folder).icon("session-shutdown") != nil)
    }

    @Test("ein unbekannter Dateiname wird gemeldet, nicht uebernommen")
    func unknownNameIsReported() throws {
        let folder = try themeFolder(["rakete.png"])
        let theme = ThemeLoader.load(at: folder)
        #expect(theme.icons.isEmpty)
        #expect(theme.issues.contains { $0.description.contains("rakete.png") })
    }

    @Test("eine fremde Endung kommt nicht durch")
    func foreignTypeIsRejected() throws {
        let folder = try themeFolder(["session-shutdown.txt"])
        let theme = ThemeLoader.load(at: folder)
        #expect(theme.icon("session-shutdown") == nil)
    }

    @Test("ein Theme aus einer einzelnen Datei hat keine Symbole")
    func singleFileThemeHasNoIcons() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("apolloshell-icons-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("Flach.css")
        try Data(":root { --apollo-accent-color: #ff0000; }".utf8).write(to: file)
        #expect(ThemeLoader.load(at: file).icons.isEmpty)
    }

    @Test("ohne Ordner icons/ ist nichts dabei, und das ist kein Hinweis")
    func withoutFolderNothingHappens() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("apolloshell-icons-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("Ohne")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(":root { --apollo-theme-name: \"Ohne\"; }".utf8).write(to: folder.appendingPathComponent("theme.css"))
        let theme = ThemeLoader.load(at: folder)
        #expect(theme.icons.isEmpty)
        #expect(theme.issues.isEmpty, "\(theme.issues.map(\.description))")
    }

    @Test("jedes Symbol hat ein eingebautes SF Symbol - ausser dem Emblem")
    func everyIconHasAFallback() {
        for icon in ThemeIconCatalog.standard.icons where icon.id != "session-emblem" {
            #expect(!icon.fallback.isEmpty, "\(icon.id) hat kein eingebautes Symbol")
        }
    }

    @Test("ein frueherer Name findet dieselbe Datei")
    func aliasesKeepWorking() {
        let catalog = ThemeIconCatalog([
            ThemeIconDescriptor(id: "session-shutdown", fallback: "power", summary: "", aliases: ["power-off"]),
        ])
        let url = URL(fileURLWithPath: "/tmp/power-off.png")
        let icons = ThemeIconSet(files: ["power-off": url])
        #expect(icons.file("session-shutdown", catalog: catalog) == url)
    }
}
