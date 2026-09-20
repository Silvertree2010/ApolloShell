import ApolloShellCore
import Testing

@Suite("Themes: the token catalogue")
struct ThemeTokenCatalogTests {
    let catalog = ThemeTokenCatalog.standard

@Test("Names are unique, in lower case and begin with --apollo-")
    func names() {
        var seen: Set<String> = []
        for token in catalog.tokens {
            #expect(token.name.hasPrefix(ThemeTokenCatalog.prefix), "\(token.name)")
            #expect(token.name == token.name.lowercased(), "\(token.name)")
            #expect(token.name.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "-" }), "\(token.name)")
            #expect(seen.insert(token.name).inserted, "\(token.name) is duplicated in the catalogue")
        }
    }

@Test("Aliases are unique and no alias is a name at the same time")
    func aliases() {
        let names = Set(catalog.tokens.map(\.name))
        var seen: Set<String> = []
        for token in catalog.tokens {
            for alias in token.aliases {
                #expect(alias.hasPrefix(ThemeTokenCatalog.prefix), "\(alias)")
                #expect(!names.contains(alias), "\(alias) is already a token name")
                #expect(seen.insert(alias).inserted, "\(alias) is duplicated")
            }
        }
    }

@Test("every default fits the type and lies in the allowed range")
    func defaultsMatchKind() {
        for token in catalog.tokens {
            for dark in [false, true] {
                let value = token.defaultValue(dark: dark)
                switch token.kind {
                case .color:
                    #expect(value.color != nil, "\(token.name)")
                case .gradient:
// A gradient is never the default: without an entry the color next to it
// colors the area as before.
                    #expect(value.gradient == ThemeGradient.none, "\(token.name)")
                case let .number(spec):
                    guard let number = value.number else {
                        #expect(Bool(false), "\(token.name) has no number as its default")
                        continue
                    }
                    #expect(number >= spec.minimum && number <= spec.maximum, "\(token.name)")
                case .text:
                    #expect(value.text != nil, "\(token.name)")
                case .file:
// No theme, no images: the default is always "nothing".
                    #expect(value.asset == ThemeAsset.none, "\(token.name)")
                case let .option(options):
                    guard let option = value.option else {
                        #expect(Bool(false), "\(token.name) has no option as its default")
                        continue
                    }
                    #expect(options.contains(option), "\(token.name)")
                    #expect(options.allSatisfy({ $0 == $0.lowercased() }), "\(token.name)")
                case .flag:
                    #expect(value.flag != nil, "\(token.name)")
                }
            }
        }
    }

@Test("every default can be written and read back exactly")
    func defaultsRoundTrip() {
        for token in catalog.tokens {
            for dark in [false, true] {
                let text = token.defaultText(dark: dark)
                let read = ThemeValueReader.read(text, kind: token.kind)
                #expect(read == token.defaultValue(dark: dark), "\(token.name): \(text)")
            }
        }
    }

@Test("contrast rules point at a color that has no rule itself")
    func contrastPartners() {
        for token in catalog.tokens {
            guard let rule = token.contrast else { continue }
            guard let partner = catalog.descriptor(named: rule.background) else {
                #expect(Bool(false), "\(token.name): \(rule.background) does not exist")
                continue
            }
            #expect(partner.kind == .color, "\(token.name)")
// Otherwise one adjustment could set off the next.
            #expect(partner.contrast == nil, "\(token.name): \(partner.name) is itself adjusted")
            #expect(rule.minimum >= 3, "\(token.name)")
            #expect(token.kind == .color, "\(token.name)")
        }
    }

@Test("the built-in theme reports nothing, and the defaults hold in both appearances")
    func standardThemeIsClean() throws {
        #expect(Theme.standard.issues.isEmpty)
        #expect(Theme.standard.formatVersion == ThemeFormat.current)
        for dark in [false, true] {
            for token in catalog.tokens {
                guard let rule = token.contrast else { continue }
                let color = try #require(token.defaultValue(dark: dark).color, "\(token.name)")
                let background = try #require(catalog.descriptor(named: rule.background)?.defaultValue(dark: dark).color,
                                              "\(rule.background)")
                let ratio = ThemeColor.contrast(color.composited(over: background), background)
                #expect(ratio >= rule.minimum, "\(token.name) dunkel=\(dark): \(ratio)")
            }
        }
    }

@Test("the short descriptions are fit for the docs")
    func summaries() {
        for token in catalog.tokens {
            #expect(!token.summary.isEmpty, "\(token.name)")
// A vertical bar would tear the Markdown table apart.
            #expect(!token.summary.contains("|"), "\(token.name)")
            #expect(!token.summary.contains("\n"), "\(token.name)")
            #expect(token.summary.allSatisfy({ $0.isASCII }), "\(token.name)")
        }
    }

    @Test("every group has at least one token", arguments: ThemeTokenGroup.allCases)
    func groupsAreUsed(group: ThemeTokenGroup) {
        #expect(catalog.tokens.contains { $0.group == group })
    }

@Test("upper and lower case do not matter when looking up")
    func lookupIgnoresCase() {
        #expect(catalog.descriptor(named: "--APOLLO-ACCENT-COLOR")?.name == "--apollo-accent-color")
        #expect(catalog.descriptor(named: "--apollo-does-not-exist") == nil)
    }

// MARK: - The promise for the coming years

/// Every name version 1 published. This list only grows; when a token is
/// renamed, the old name stays as an alias and this test stays green.
/// Whoever strikes something here breaks other people's themes.
    static let version1: [String] = [
        "--apollo-theme-format", "--apollo-theme-name", "--apollo-theme-author",
        "--apollo-theme-description", "--apollo-theme-version", "--apollo-theme-homepage",
        "--apollo-theme-author-image", "--apollo-theme-appearance",
        "--apollo-background-color", "--apollo-background-image", "--apollo-background-image-opacity",
        "--apollo-background-fit", "--apollo-surface-color", "--apollo-surface-opacity",
        "--apollo-elevated-surface-color", "--apollo-separator-color", "--apollo-border-color",
        "--apollo-border-width", "--apollo-shadow-opacity",
        "--apollo-text-color", "--apollo-secondary-text-color", "--apollo-muted-text-color",
        "--apollo-link-color", "--apollo-on-accent-color",
        "--apollo-accent-color", "--apollo-secondary-accent-color", "--apollo-selection-color",
        "--apollo-hover-color", "--apollo-success-color", "--apollo-warning-color", "--apollo-danger-color",
        "--apollo-bar-color", "--apollo-bar-opacity", "--apollo-bar-text-color", "--apollo-bar-icon-color",
        "--apollo-bar-width", "--apollo-bar-radius", "--apollo-bar-padding", "--apollo-bar-item-spacing",
        "--apollo-bar-blur",
        "--apollo-dock-icon-size", "--apollo-dock-spacing", "--apollo-dock-indicator-color",
        "--apollo-panel-color", "--apollo-panel-opacity", "--apollo-panel-radius", "--apollo-panel-padding",
        "--apollo-panel-blur", "--apollo-card-color", "--apollo-card-radius",
        "--apollo-launcher-highlight-color", "--apollo-launcher-row-height",
        "--apollo-font-family", "--apollo-monospace-font-family", "--apollo-font-size", "--apollo-font-weight",
        "--apollo-corner-radius", "--apollo-control-radius", "--apollo-spacing", "--apollo-animation-speed",
        "--apollo-animations", "--apollo-glass", "--apollo-shadows", "--apollo-icon-style",
        "--apollo-toast-color", "--apollo-toast-text-color", "--apollo-toast-radius",
    ]

    @Test("a name that was published once never disappears", arguments: ThemeTokenCatalogTests.version1)
    func publishedNamesStay(name: String) {
        #expect(catalog.contains(name), "\(name) is missing from the catalogue")
    }

@Test("version 1 has lost no token")
    func noneLost() {
        #expect(catalog.tokens.count >= ThemeTokenCatalogTests.version1.count)
    }

@Test("renaming means: the old name goes on holding")
    func renamedTokenKeepsOldName() {
// No real token has been renamed so far; what is checked is the way there,
// so that it works the first time.
        let renamed = ThemeTokenDescriptor(
            name: "--apollo-new-color", kind: .color, defaultValue: .color(.black),
            summary: "Test", group: .accent, aliases: ["--apollo-old-color"]
        )
        let catalog = ThemeTokenCatalog([renamed])
        let sheet = ThemeStyleSheetParser.parse(":root { --apollo-old-color: #ff0000; }")
        let theme = Theme.make(identifier: "alt", styleSheet: sheet, catalog: catalog)
        #expect(theme.value("--apollo-new-color")?.color == ThemeColor(hex: 0xFF0000))
        #expect(theme.issues.isEmpty)
    }

// MARK: - The typed handles

    private func tag(_ kind: ThemeTokenKind?) -> String {
        switch kind {
        case .color: "color"
        case .gradient: "gradient"
        case .number: "number"
        case .text: "text"
        case .file: "file"
        case .option: "option"
        case .flag: "flag"
        case nil: "missing"
        }
    }

    @Test("every handle in the code points at a token of the right type")
    func handlesPointAtTokens() {
        let colors: [ThemeColorToken] = [
            .background, .surface, .elevatedSurface, .separator, .border,
            .text, .secondaryText, .mutedText, .link, .onAccent,
            .accent, .secondaryAccent, .selection, .hover, .success, .warning, .danger,
            .bar, .barText, .barIcon, .dockIndicator, .panel, .card,
            .launcherHighlight, .toast, .toastText,
        ]
        for token in colors { #expect(tag(token.descriptor?.kind) == "color", "\(token.name)") }

        let numbers: [ThemeNumberToken] = [
            .format, .backgroundImageOpacity, .surfaceOpacity, .shadowOpacity, .borderWidth,
            .barWidth, .barRadius, .barPadding, .barItemSpacing, .barOpacity, .barBlur,
            .dockIconSize, .dockSpacing, .panelRadius, .panelPadding, .panelOpacity, .panelBlur,
            .cardRadius, .launcherRowHeight, .fontSize, .fontWeight,
            .cornerRadius, .controlRadius, .spacing, .animationSpeed, .toastRadius,
        ]
        for token in numbers { #expect(tag(token.descriptor?.kind) == "number", "\(token.name)") }

        let texts: [ThemeTextToken] = [
            .themeName, .author, .themeDescription, .version, .homepage,
            .fontFamily, .monospaceFontFamily,
        ]
        for token in texts { #expect(tag(token.descriptor?.kind) == "text", "\(token.name)") }

        let gradients: [ThemeGradientToken] = [
            .background, .surface, .accent, .bar, .panel, .card, .launcherHighlight, .toast,
        ]
        for token in gradients { #expect(tag(token.descriptor?.kind) == "gradient", "\(token.name)") }

        let files: [ThemeFileToken] = [.authorImage, .backgroundImage]
        for token in files { #expect(tag(token.descriptor?.kind) == "file", "\(token.name)") }

        let options: [ThemeOptionToken] = [.appearance, .backgroundFit, .iconStyle]
        for token in options { #expect(tag(token.descriptor?.kind) == "option", "\(token.name)") }

        let flags: [ThemeFlagToken] = [.animations, .glass, .shadows]
        for token in flags { #expect(tag(token.descriptor?.kind) == "flag", "\(token.name)") }
    }
}
