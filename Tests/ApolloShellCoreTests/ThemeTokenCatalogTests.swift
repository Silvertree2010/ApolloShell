import ApolloShellCore
import Testing

@Suite("Themes: Token-Verzeichnis")
struct ThemeTokenCatalogTests {
    let catalog = ThemeTokenCatalog.standard

    @Test("Namen sind eindeutig, klein geschrieben und beginnen mit --apollo-")
    func names() {
        var seen: Set<String> = []
        for token in catalog.tokens {
            #expect(token.name.hasPrefix(ThemeTokenCatalog.prefix), "\(token.name)")
            #expect(token.name == token.name.lowercased(), "\(token.name)")
            #expect(token.name.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "-" }), "\(token.name)")
            #expect(seen.insert(token.name).inserted, "\(token.name) steht doppelt im Verzeichnis")
        }
    }

    @Test("Aliasse sind eindeutig und kein Alias ist zugleich ein Name")
    func aliases() {
        let names = Set(catalog.tokens.map(\.name))
        var seen: Set<String> = []
        for token in catalog.tokens {
            for alias in token.aliases {
                #expect(alias.hasPrefix(ThemeTokenCatalog.prefix), "\(alias)")
                #expect(!names.contains(alias), "\(alias) ist schon ein Tokenname")
                #expect(seen.insert(alias).inserted, "\(alias) steht doppelt")
            }
        }
    }

    @Test("jede Vorgabe passt zum Typ und liegt im erlaubten Bereich")
    func defaultsMatchKind() {
        for token in catalog.tokens {
            for dark in [false, true] {
                let value = token.defaultValue(dark: dark)
                switch token.kind {
                case .color:
                    #expect(value.color != nil, "\(token.name)")
                case .gradient:
                    // Ein Verlauf ist nie die Vorgabe: ohne Angabe faerbt die
                    // Farbe daneben die Flaeche wie bisher.
                    #expect(value.gradient == ThemeGradient.none, "\(token.name)")
                case let .number(spec):
                    guard let number = value.number else {
                        #expect(Bool(false), "\(token.name) hat keine Zahl als Vorgabe")
                        continue
                    }
                    #expect(number >= spec.minimum && number <= spec.maximum, "\(token.name)")
                case .text:
                    #expect(value.text != nil, "\(token.name)")
                case .file:
                    // Kein Theme, keine Bilder: Vorgabe ist immer "nichts".
                    #expect(value.asset == ThemeAsset.none, "\(token.name)")
                case let .option(options):
                    guard let option = value.option else {
                        #expect(Bool(false), "\(token.name) hat keine Aufzaehlung als Vorgabe")
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

    @Test("jede Vorgabe laesst sich schreiben und genau so wieder lesen")
    func defaultsRoundTrip() {
        for token in catalog.tokens {
            for dark in [false, true] {
                let text = token.defaultText(dark: dark)
                let read = ThemeValueReader.read(text, kind: token.kind)
                #expect(read == token.defaultValue(dark: dark), "\(token.name): \(text)")
            }
        }
    }

    @Test("Kontrastregeln zeigen auf eine Farbe, die selbst keine Regel hat")
    func contrastPartners() {
        for token in catalog.tokens {
            guard let rule = token.contrast else { continue }
            guard let partner = catalog.descriptor(named: rule.background) else {
                #expect(Bool(false), "\(token.name): \(rule.background) gibt es nicht")
                continue
            }
            #expect(partner.kind == .color, "\(token.name)")
            // Sonst koennte eine Anpassung die naechste ausloesen.
            #expect(partner.contrast == nil, "\(token.name): \(partner.name) wird selbst angepasst")
            #expect(rule.minimum >= 3, "\(token.name)")
            #expect(token.kind == .color, "\(token.name)")
        }
    }

    @Test("das eingebaute Theme meldet nichts und ist in beiden Erscheinungsbildern lesbar")
    func standardThemeIsClean() {
        #expect(Theme.standard.issues.isEmpty)
        #expect(Theme.standard.formatVersion == ThemeFormat.current)
        for dark in [false, true] {
            for token in catalog.tokens {
                guard let rule = token.contrast,
                      let color = Theme.standard.value(token.name, dark: dark)?.color,
                      let background = Theme.standard.value(rule.background, dark: dark)?.color else { continue }
                let ratio = ThemeColor.contrast(color.composited(over: background), background)
                #expect(ratio >= rule.minimum, "\(token.name) dunkel=\(dark): \(ratio)")
            }
        }
    }

    @Test("Kurzbeschreibungen taugen fuer die Doku")
    func summaries() {
        for token in catalog.tokens {
            #expect(!token.summary.isEmpty, "\(token.name)")
            // Ein senkrechter Strich wuerde die Markdown-Tabelle zerreissen.
            #expect(!token.summary.contains("|"), "\(token.name)")
            #expect(!token.summary.contains("\n"), "\(token.name)")
            #expect(token.summary.allSatisfy({ $0.isASCII }), "\(token.name)")
        }
    }

    @Test("jede Gruppe hat mindestens ein Token", arguments: ThemeTokenGroup.allCases)
    func groupsAreUsed(group: ThemeTokenGroup) {
        #expect(catalog.tokens.contains { $0.group == group })
    }

    @Test("Gross- und Kleinschreibung ist beim Nachschlagen egal")
    func lookupIgnoresCase() {
        #expect(catalog.descriptor(named: "--APOLLO-ACCENT-COLOR")?.name == "--apollo-accent-color")
        #expect(catalog.descriptor(named: "--apollo-gibt-es-nicht") == nil)
    }

    // MARK: - Die Zusicherung fuer die naechsten Jahre

    /// Jeder Name, den Fassung 1 veroeffentlicht hat. Diese Liste waechst nur;
    /// wird ein Token umbenannt, bleibt der alte Name als Alias bestehen und
    /// dieser Test gruen. Wer hier etwas streicht, macht fremde Themes kaputt.
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

    @Test("ein einmal veroeffentlichter Name verschwindet nie", arguments: ThemeTokenCatalogTests.version1)
    func publishedNamesStay(name: String) {
        #expect(catalog.contains(name), "\(name) fehlt im Verzeichnis")
    }

    @Test("Fassung 1 hat kein Token verloren")
    func noneLost() {
        #expect(catalog.tokens.count >= ThemeTokenCatalogTests.version1.count)
    }

    @Test("umbenennen heisst: der alte Name gilt weiter")
    func renamedTokenKeepsOldName() {
        // Kein echtes Token wurde bisher umbenannt; geprueft wird der Weg
        // dorthin, damit er beim ersten Mal funktioniert.
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

    // MARK: - Die getippten Griffe

    private func tag(_ kind: ThemeTokenKind?) -> String {
        switch kind {
        case .color: "color"
        case .gradient: "gradient"
        case .number: "number"
        case .text: "text"
        case .file: "file"
        case .option: "option"
        case .flag: "flag"
        case nil: "fehlt"
        }
    }

    @Test("jeder Griff im Code zeigt auf ein Token des richtigen Typs")
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
