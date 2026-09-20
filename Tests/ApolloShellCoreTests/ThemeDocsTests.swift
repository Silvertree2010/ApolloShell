import ApolloShellCore
import Foundation
import Testing

/// Pins docs/THEMES.md and the examples to the catalogue.
///
/// Documentation that is kept up by hand is no longer right after the third
/// new token - and wrong documentation is worse than none, because somebody
/// writes a theme by it. So the core generates the tables, and these tests
/// insist that exactly those stand in the file.
@Suite("Themes: docs and examples")
struct ThemeDocsTests {
    /// The root folder of the project, worked out from this file:
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

    /// Every token name that turns up in a text.
    private func mentionedTokens(in text: String) -> Set<String> {
        var found: Set<String> = []
        var rest = Substring(text)
        while let start = rest.range(of: ThemeTokenCatalog.prefix) {
            var end = start.upperBound
            while end < rest.endIndex, rest[end].isLowercase || rest[end].isNumber || rest[end] == "-" {
                end = rest.index(after: end)
            }
            var name = String(rest[start.lowerBound..<end])
            // `--apollo-…` in a sentence is no token name.
            while name.hasSuffix("-") { name.removeLast() }
            found.insert(name)
            rest = rest[end...]
        }
        return found.filter { $0.count > ThemeTokenCatalog.prefix.count }
    }

    @Test("the token tables in docs/THEMES.md come out of the catalogue")
    func tablesMatchCatalog() throws {
        let text = try read(Self.docs)
        let tables = ThemeDocumentation.markdownTables()
        #expect(text.contains(tables), """
        docs/THEMES.md is no longer in sync with the catalogue. \
        Insert the generated tables (ThemeDocumentation.markdownTables()).
        """)
    }

    @Test("the docs invent no tokens")
    func docsMentionOnlyRealTokens() throws {
        for name in mentionedTokens(in: try read(Self.docs)) {
            #expect(ThemeTokenCatalog.standard.contains(name), "\(name) is in the docs but not in the catalogue")
        }
    }

    @Test("every name used earlier stands in the docs")
    func aliasesAreDocumented() throws {
        let text = try read(Self.docs)
        for token in ThemeTokenCatalog.standard.tokens {
            for alias in token.aliases {
                #expect(text.contains(alias), "\(alias) is missing from docs/THEMES.md")
            }
        }
    }

    @Test("every limit out of ThemeLimits stands in the docs")
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
            #expect(text.contains(extensionName), "\(extensionName) is missing from docs/THEMES.md")
        }
    }

    // MARK: - The examples

    @Test("the small example loads without a single notice")
    func minimalExample() {
        let theme = ThemeLoader.load(at: Self.examples.appendingPathComponent("minimal.css"))
        #expect(theme.identifier == "minimal")
        #expect(theme.title == "Minimal")
        #expect(theme.issues.isEmpty, "\(theme.issues.map(\.description))")
        #expect(theme.color(.accent) == ThemeColor(hex: 0xFF6B35))
        #expect(theme.color(.accent, dark: true) == ThemeColor(hex: 0xFF8354))
        // What it does not set stays empty - light as well as dark.
        #expect(theme.color(.surface) == nil)
        #expect(theme.color(.surface, dark: true) == nil)
    }

    @Test("the full example names every token")
    func fullExampleIsComplete() throws {
        let text = try read(Self.examples.appendingPathComponent("full/theme.css"))
        for token in ThemeTokenCatalog.standard.tokens {
            #expect(text.contains(token.name + ":"), "\(token.name) is missing from examples/themes/full/theme.css")
        }
        for name in mentionedTokens(in: text) {
            #expect(ThemeTokenCatalog.standard.contains(name), "\(name) does not exist")
        }
    }

    @Test("the full example loads without a notice and gives exactly the defaults")
    func fullExampleMatchesDefaults() {
        let theme = ThemeLoader.load(at: Self.examples.appendingPathComponent("full"))
        #expect(theme.identifier == "full")
        #expect(theme.issues.isEmpty, "\(theme.issues.map(\.description))")
        #expect(theme.formatVersion == ThemeFormat.current)

        // The proof that writing and reading mean the same: every token but
        // the entries about the theme itself stands at the default again.
        for token in ThemeTokenCatalog.standard.tokens where token.group != .meta {
            if token.name == ThemeFileToken.backgroundImage.name { continue }
            #expect(theme.value(token.name) == token.defaultValue, "\(token.name) light")
            #expect(theme.value(token.name, dark: true) == token.darkDefaultValue, "\(token.name) dark")
        }
    }

    @Test("the full example brings its images with it")
    func fullExampleHasImages() {
        let folder = Self.examples.appendingPathComponent("full")
        let theme = ThemeLoader.load(at: folder)
        #expect(theme.file(.backgroundImage)?.lastPathComponent == "background.png")
        #expect(theme.file(.authorImage)?.lastPathComponent == "author.png")
        // And out of its own folder at that, not from anywhere.
        for url in [theme.file(.backgroundImage), theme.file(.authorImage)] {
            #expect(url?.path.hasPrefix(folder.resolvingSymlinksInPath().path) == true)
        }
        #expect(theme.author == "Alex")
        #expect(theme.title == "Everything")
    }

    @Test("all examples lie in the same folder and are found")
    func allExamplesAreThemes() {
        #expect(ThemeLoader.themes(in: Self.examples).map(\.identifier) == ["full", "minimal", "Nightfall"])
    }

    @Test("the gradient example loads without a notice and sets gradients")
    func gradientExample() {
        let theme = ThemeLoader.load(at: Self.examples.appendingPathComponent("Nightfall.css"))
        #expect(theme.title == "Nightfall")
        #expect(theme.issues.isEmpty, "\(theme.issues.map(\.description))")
        #expect(theme.gradient(.bar, dark: true)?.stops.count == 2)
        #expect(theme.gradient(.panel)?.isEmpty ?? true, "no gradient in the light appearance")
        #expect(theme.color(.accent) == ThemeColor(hex: 0xFF8A3D))
    }
}
