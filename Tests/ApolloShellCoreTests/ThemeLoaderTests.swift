import ApolloShellCore
import Foundation
import Testing

@Suite("Themes: von der Platte lesen")
struct ThemeLoaderTests {
    /// Reicht als Datei - geprueft wird der Pfad, nicht der Bildinhalt.
    private let pixel = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    private func tempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("apolloshell-themes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func write(_ text: String, to url: URL) throws -> URL {
        try Data(text.utf8).write(to: url)
        return url
    }

    @discardableResult
    private func folderTheme(in root: URL, named name: String, css: String) throws -> URL {
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write(css, to: folder.appendingPathComponent(ThemeLoader.styleSheetName))
        return folder
    }

    // MARK: - Aufbau

    @Test("eine verknuepfte .css-Datei ist ein Theme")
    func symlinkedFile() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let elsewhere = root.appendingPathComponent("dotfiles")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let target = try write(":root { --apollo-accent-color: #ff0000; }",
                               to: elsewhere.appendingPathComponent("Linked.css"))
        let themes = root.appendingPathComponent("themes")
        try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: themes.appendingPathComponent("Linked.css"),
                                                   withDestinationURL: target)
        let found = ThemeLoader.themes(in: themes)
        #expect(found.map(\.identifier) == ["Linked"])
        #expect(found.first?.color(.accent) == ThemeColor(hex: 0xFF0000))
        #expect(found.first?.issues.isEmpty == true)
    }

    @Test("ein verknuepfter Theme-Ordner wird gefunden, Bilder darin gelten")
    func symlinkedFolder() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try folderTheme(in: root, named: "Echt", css: """
        :root { --apollo-background-image: url("bg.png"); }
        """)
        try pixel.write(to: folder.appendingPathComponent("bg.png"))
        let themes = root.appendingPathComponent("themes")
        try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: themes.appendingPathComponent("Link"),
                                                   withDestinationURL: folder)
        let found = ThemeLoader.themes(in: themes)
        #expect(found.map(\.identifier) == ["Link"])
        #expect(found.first?.issues.isEmpty == true)
    }

    @Test("theme.css, die aus dem Ordner hinaus zeigt, gilt nicht")
    func styleSheetLinkOutsideFolder() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = try write(":root { --apollo-accent-color: #00ff00; }",
                                to: root.appendingPathComponent("outside.css"))
        let folder = root.appendingPathComponent("Fremd")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent(ThemeLoader.styleSheetName), withDestinationURL: outside)
        let theme = ThemeLoader.load(at: folder)
        #expect(theme.color(.accent) != ThemeColor(hex: 0x00FF00))
        #expect(theme.issues.contains { if case .unreadableFile = $0.kind { true } else { false } })
    }

    @Test("eine einzelne .css-Datei ist ein Theme")
    func singleFile() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try write(":root { --apollo-accent-color: #ff0000; }",
                             to: root.appendingPathComponent("Sunset.css"))
        let theme = ThemeLoader.load(at: file)
        #expect(theme.identifier == "Sunset")
        #expect(theme.slug == "sunset")
        #expect(theme.color(.accent) == ThemeColor(hex: 0xFF0000))
        #expect(theme.issues.isEmpty)
    }

    @Test("ein Ordner mit theme.css ist ein Theme, Bilder daneben gelten")
    func folderWithImage() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try folderTheme(in: root, named: "Abend", css: """
        :root {
          --apollo-background-image: url("bg.png");
          --apollo-theme-author-image: url("bilder/autor.png");
        }
        """)
        try pixel.write(to: folder.appendingPathComponent("bg.png"))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("bilder"),
                                                withIntermediateDirectories: true)
        try pixel.write(to: folder.appendingPathComponent("bilder/autor.png"))

        let theme = ThemeLoader.load(at: folder)
        #expect(theme.identifier == "Abend")
        #expect(theme.file(.backgroundImage)?.lastPathComponent == "bg.png")
        #expect(theme.file(.authorImage)?.lastPathComponent == "autor.png")
        #expect(theme.issues.isEmpty)
    }

    @Test("ein Ordner ohne theme.css ist kein Theme")
    func folderWithoutStyleSheet() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Leer")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let theme = ThemeLoader.load(at: folder)
        #expect(theme.color(.accent) == nil)
        #expect(theme.issues.contains(ThemeIssue(.unreadableFile(ThemeLoader.styleSheetName))))
    }

    @Test("was es nicht gibt, ergibt die Vorgaben und einen Hinweis")
    func missingFile() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let theme = ThemeLoader.load(at: root.appendingPathComponent("weg.css"))
        #expect(theme.identifier == "weg")
        #expect(theme.issues.contains(ThemeIssue(.unreadableFile("weg.css"))))
    }

    @Test("alle Themes eines Ordners, sortiert, ohne Beiwerk")
    func listing() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(":root {}", to: root.appendingPathComponent("B.css"))
        try write(":root {}", to: root.appendingPathComponent("a.css"))
        try write("kein Theme", to: root.appendingPathComponent("notizen.txt"))
        try write(":root {}", to: root.appendingPathComponent(".versteckt.css"))
        try folderTheme(in: root, named: "Ordner", css: ":root {}")
        let ohne = root.appendingPathComponent("OhneCSS")
        try FileManager.default.createDirectory(at: ohne, withIntermediateDirectories: true)

        #expect(ThemeLoader.themes(in: root).map(\.identifier) == ["a", "B", "Ordner"])
        #expect(ThemeLoader.themes(in: root.appendingPathComponent("gibtesnicht")).isEmpty)
    }

    @Test("der Themes-Ordner liegt neben settings.json")
    func folderPath() {
        let support = URL(fileURLWithPath: "/Beispiel/Application Support/ApolloShell")
        #expect(ThemeLoader.folder(inApplicationSupport: support).lastPathComponent == "themes")
    }

    // MARK: - Sicherheit

    @Test("ein Theme kommt nicht aus seinem Ordner heraus")
    func assetsStayInsideTheFolder() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // Etwas, das ein boesartiges Theme gerne haette.
        let secret = root.appendingPathComponent("secret.png")
        try pixel.write(to: secret)
        let folder = try folderTheme(in: root, named: "Angriff", css: ":root {}")
        try pixel.write(to: folder.appendingPathComponent("ok.png"))
        try write("nur Text", to: folder.appendingPathComponent("notizen.txt"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.png"),
                                                   withDestinationURL: secret)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("hinaus"),
                                                   withDestinationURL: root)

        let attacks: [(String, ThemeAssetRejection)] = [
            ("../secret.png", .escapesFolder),
            ("../../secret.png", .escapesFolder),
            ("sub/../../secret.png", .escapesFolder),
            ("%2e%2e/secret.png", .escapesFolder),
            ("..%2Fsecret.png", .escapesFolder),
            ("/etc/hosts.png", .escapesFolder),
            ("~/Pictures/x.png", .escapesFolder),
            ("https://example.com/x.png", .notALocalPath),
            ("http://example.com/x.png", .notALocalPath),
            ("file:///etc/hosts.png", .notALocalPath),
            ("data:image/png;base64,AAAA", .notALocalPath),
            ("link.png", .outsideThemeFolder),
            ("hinaus/secret.png", .outsideThemeFolder),
            ("notizen.txt", .unsupportedType("txt")),
            ("fehlt.png", .missing),
        ]
        for (reference, expected) in attacks {
            let css = ":root { --apollo-background-image: url(\"\(reference)\"); }"
            let theme = Theme.make(identifier: "Angriff",
                                   styleSheet: ThemeStyleSheetParser.parse(css),
                                   assets: .folder(folder))
            #expect(theme.file(.backgroundImage) == nil, "\(reference) haette abgelehnt werden muessen")
            #expect(theme.issues.contains(where: { $0.kind == .rejectedAsset(reference: reference, reason: expected) }),
                    "\(reference): \(theme.issues.map(\.description))")
        }

        // Und was erlaubt ist, geht auch wirklich.
        let good = Theme.make(identifier: "Angriff",
                              styleSheet: ThemeStyleSheetParser.parse(
                                  ":root { --apollo-background-image: url(\"ok.png\"); }"),
                              assets: .folder(folder))
        #expect(good.file(.backgroundImage)?.lastPathComponent == "ok.png")
        #expect(good.issues.isEmpty)
    }

    @Test("ein Bild, das zu gross ist, wird nicht benutzt")
    func assetTooLarge() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try folderTheme(in: root, named: "Gross", css: ":root {}")
        try pixel.write(to: folder.appendingPathComponent("bg.png"))
        let limits = ThemeLimits(maxAssetBytes: 4)
        let theme = Theme.make(identifier: "Gross",
                               styleSheet: ThemeStyleSheetParser.parse(
                                   ":root { --apollo-background-image: url(\"bg.png\"); }"),
                               assets: .folder(folder, limits: limits), limits: limits)
        #expect(theme.file(.backgroundImage) == nil)
        #expect(theme.issues.contains {
            $0.kind == .rejectedAsset(reference: "bg.png", reason: .tooLarge(bytes: pixel.count, limit: 4))
        })
    }

    @Test("eine einzelne .css-Datei bekommt keine Bilder aus dem Themes-Ordner")
    func singleFileHasNoAssets() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try pixel.write(to: root.appendingPathComponent("fremd.png"))
        let file = try write(":root { --apollo-background-image: url(\"fremd.png\"); }",
                             to: root.appendingPathComponent("Neugierig.css"))
        let theme = ThemeLoader.load(at: file)
        #expect(theme.file(.backgroundImage) == nil)
        #expect(theme.issues.contains {
            $0.kind == .rejectedAsset(reference: "fremd.png", reason: .needsThemeFolder)
        })
    }

    // MARK: - Kaputte Dateien

    @Test("leere Datei: die Vorgaben, ohne Aufhebens")
    func emptyFile() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try write("", to: root.appendingPathComponent("Leer.css"))
        let theme = ThemeLoader.load(at: file)
        #expect(theme.color(.accent) == nil)
        #expect(theme.issues.isEmpty)
    }

    @Test("Binaerdaten: kein Absturz, die Vorgaben, ein Hinweis")
    func binaryFile() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Bild.css")
        try Data((0..<4096).map { UInt8($0 % 256) }).write(to: file)
        let theme = ThemeLoader.load(at: file)
        #expect(theme.color(.accent) == nil)
        #expect(theme.issues.contains(ThemeIssue(.notText)))
    }

    @Test("falsche Kodierung: als Latin-1 gelesen, mit Hinweis")
    func latin1File() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Latin.css")
        let css = ":root { --apollo-theme-name: \"Grün\"; --apollo-accent-color: #ff0000; }"
        try #require(css.data(using: .isoLatin1)).write(to: file)
        let theme = ThemeLoader.load(at: file)
        #expect(theme.text(.themeName) == "Grün")
        #expect(theme.color(.accent) == ThemeColor(hex: 0xFF0000))
        #expect(theme.issues.contains(ThemeIssue(.notUTF8)))
    }

    @Test("Byte-Reihenfolge-Marke stoert nicht")
    func byteOrderMark() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("BOM.css")
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(":root { --apollo-accent-color: #ff0000; }".utf8))
        try data.write(to: file)
        let theme = ThemeLoader.load(at: file)
        #expect(theme.color(.accent) == ThemeColor(hex: 0xFF0000))
        #expect(theme.issues.isEmpty)
    }

    @Test("zu grosse Datei wird gar nicht erst gelesen")
    func styleSheetTooLarge() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Riesig.css")
        let filler = String(repeating: "/* Fuellung, damit es weh tut */\n", count: 20_000)
        try write(":root { --apollo-accent-color: #ff0000; }\n" + filler, to: file)
        let theme = ThemeLoader.load(at: file)
        #expect(theme.color(.accent) == nil)
        #expect(theme.issues.contains { if case .styleSheetTooLarge = $0.kind { true } else { false } })
    }

    @Test("eine grosse, aber erlaubte Datei wird noch gelesen")
    func largeButAllowed() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Gross.css")
        let filler = String(repeating: "/* Kommentar */\n", count: 20_000) // rund 320 KB
        try write(filler + ":root { --apollo-accent-color: #ff0000; }\n", to: file)
        let theme = ThemeLoader.load(at: file)
        #expect(theme.color(.accent) == ThemeColor(hex: 0xFF0000))
    }

    @Test("Kodierung erkennen", arguments: [
        (Data(), true), (Data([0x00, 0x01]), false), (Data("/* ok */".utf8), true),
    ])
    func decoding(data: Data, readable: Bool) {
        #expect((ThemeLoader.decode(data).text != nil) == readable)
    }
}
