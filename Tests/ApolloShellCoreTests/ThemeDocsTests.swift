import ApolloShellCore
import Foundation
import Testing

/// Haelt docs/THEMES.md und die Beispiele am Verzeichnis fest.
///
/// Eine Doku, die von Hand nachgezogen wird, stimmt nach dem dritten neuen
/// Token nicht mehr - und eine falsche Doku ist schlimmer als keine, weil
/// jemand danach ein Theme schreibt. Deshalb erzeugt der Kern die Tabellen,
/// und diese Tests bestehen darauf, dass genau sie in der Datei stehen.
@Suite("Themes: Doku und Beispiele")
struct ThemeDocsTests {
    /// Das Wurzelverzeichnis des Projekts, von dieser Datei aus gerechnet:
    /// Tests/ApolloShellCoreTests/ThemeDocsTests.swift
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let docs = root.appendingPathComponent("docs/THEMES.md")
    private static let examples = root.appendingPathComponent("examples/themes")

    private func read(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    /// Jeder Tokenname, der in einem Text vorkommt.
    private func mentionedTokens(in text: String) -> Set<String> {
        var found: Set<String> = []
        var rest = Substring(text)
        while let start = rest.range(of: ThemeTokenCatalog.prefix) {
            var end = start.upperBound
            while end < rest.endIndex, rest[end].isLowercase || rest[end].isNumber || rest[end] == "-" {
                end = rest.index(after: end)
            }
            var name = String(rest[start.lowerBound..<end])
            // `--apollo-…` in einem Satz ist kein Tokenname.
            while name.hasSuffix("-") { name.removeLast() }
            found.insert(name)
            rest = rest[end...]
        }
        return found.filter { $0.count > ThemeTokenCatalog.prefix.count }
    }

    @Test("die Token-Tabellen in docs/THEMES.md stammen aus dem Verzeichnis")
    func tablesMatchCatalog() throws {
        let text = try read(Self.docs)
        let tables = ThemeDocumentation.markdownTables()
        #expect(text.contains(tables), """
        docs/THEMES.md ist nicht mehr auf dem Stand des Verzeichnisses. \
        Die erzeugten Tabellen einsetzen (ThemeDocumentation.markdownTables()).
        """)
    }

    @Test("die Doku erfindet keine Token")
    func docsMentionOnlyRealTokens() throws {
        for name in mentionedTokens(in: try read(Self.docs)) {
            #expect(ThemeTokenCatalog.standard.contains(name), "\(name) steht in der Doku, aber nicht im Verzeichnis")
        }
    }

    @Test("jeder frueher benutzte Name steht in der Doku")
    func aliasesAreDocumented() throws {
        let text = try read(Self.docs)
        for token in ThemeTokenCatalog.standard.tokens {
            for alias in token.aliases {
                #expect(text.contains(alias), "\(alias) fehlt in docs/THEMES.md")
            }
        }
    }

    @Test("jede Grenze aus ThemeLimits steht in der Doku")
    func limitsAreDocumented() throws {
        let text = try read(Self.docs)
        let limits = ThemeLimits.standard
        #expect(text.contains("512 KiB"))
        #expect(limits.maxStyleSheetBytes == 512 * 1024)
        #expect(text.contains("8 MiB"))
        #expect(limits.maxAssetBytes == 8 * 1024 * 1024)
        #expect(text.contains("\(limits.maxDeclarations) declarations"))
        #expect(text.contains("\(limits.maxTextLength) characters"))
        for extensionName in limits.imageExtensions {
            #expect(text.contains(extensionName), "\(extensionName) fehlt in docs/THEMES.md")
        }
    }

    // MARK: - Die Beispiele

    @Test("das kleine Beispiel laedt ohne einen einzigen Hinweis")
    func minimalExample() {
        let theme = ThemeLoader.load(at: Self.examples.appendingPathComponent("minimal.css"))
        #expect(theme.identifier == "minimal")
        #expect(theme.title == "Minimal")
        #expect(theme.issues.isEmpty, "\(theme.issues.map(\.description))")
        #expect(theme.color(.accent) == ThemeColor(hex: 0xFF6B35))
        #expect(theme.color(.accent, dark: true) == ThemeColor(hex: 0xFF8354))
        // Was es nicht setzt, bleibt leer - hell wie dunkel.
        #expect(theme.color(.surface) == nil)
        #expect(theme.color(.surface, dark: true) == nil)
    }

    @Test("das vollstaendige Beispiel nennt jedes Token")
    func fullExampleIsComplete() throws {
        let text = try read(Self.examples.appendingPathComponent("full/theme.css"))
        for token in ThemeTokenCatalog.standard.tokens {
            #expect(text.contains(token.name + ":"), "\(token.name) fehlt in examples/themes/full/theme.css")
        }
        for name in mentionedTokens(in: text) {
            #expect(ThemeTokenCatalog.standard.contains(name), "\(name) gibt es nicht")
        }
    }

    @Test("das vollstaendige Beispiel laedt ohne Hinweis und ergibt genau die Vorgaben")
    func fullExampleMatchesDefaults() {
        let theme = ThemeLoader.load(at: Self.examples.appendingPathComponent("full"))
        #expect(theme.identifier == "full")
        #expect(theme.issues.isEmpty, "\(theme.issues.map(\.description))")
        #expect(theme.formatVersion == ThemeFormat.current)

        // Der Beweis, dass Schreiben und Lesen dasselbe meinen: jedes Token
        // ausser den Angaben zum Theme selbst steht wieder auf der Vorgabe.
        for token in ThemeTokenCatalog.standard.tokens where token.group != .meta {
            if token.name == ThemeFileToken.backgroundImage.name { continue }
            #expect(theme.value(token.name) == token.defaultValue, "\(token.name) hell")
            #expect(theme.value(token.name, dark: true) == token.darkDefaultValue, "\(token.name) dunkel")
        }
    }

    @Test("das vollstaendige Beispiel bringt seine Bilder mit")
    func fullExampleHasImages() {
        let folder = Self.examples.appendingPathComponent("full")
        let theme = ThemeLoader.load(at: folder)
        #expect(theme.file(.backgroundImage)?.lastPathComponent == "background.png")
        #expect(theme.file(.authorImage)?.lastPathComponent == "author.png")
        // Und zwar aus dem eigenen Ordner, nicht von irgendwoher.
        for url in [theme.file(.backgroundImage), theme.file(.authorImage)] {
            #expect(url?.path.hasPrefix(folder.resolvingSymlinksInPath().path) == true)
        }
        #expect(theme.author == "Alex")
        #expect(theme.title == "Everything")
    }

    @Test("alle Beispiele liegen im selben Ordner und werden gefunden")
    func allExamplesAreThemes() {
        #expect(ThemeLoader.themes(in: Self.examples).map(\.identifier) == ["full", "minimal", "Nightfall"])
    }

    @Test("das Verlaufs-Beispiel laedt ohne Hinweis und setzt Verlaeufe")
    func gradientExample() {
        let theme = ThemeLoader.load(at: Self.examples.appendingPathComponent("Nightfall.css"))
        #expect(theme.title == "Nightfall")
        #expect(theme.issues.isEmpty, "\(theme.issues.map(\.description))")
        #expect(theme.gradient(.bar, dark: true)?.stops.count == 2)
        #expect(theme.gradient(.panel)?.isEmpty ?? true, "im hellen Erscheinungsbild ohne Verlauf")
        #expect(theme.color(.accent) == ThemeColor(hex: 0xFF8A3D))
    }
}
