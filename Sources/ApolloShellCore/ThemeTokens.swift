import Foundation

/// Wozu ein Token gehoert. Nur zum Gruppieren in der Doku und spaeter in
/// Nexus - die Zugehoerigkeit darf sich aendern, der Name nie.
public enum ThemeTokenGroup: String, Equatable, Hashable, Sendable, CaseIterable {
    case meta = "Metadata"
    case surface = "Surfaces"
    case text = "Text"
    case accent = "Accent and state"
    case bar = "Sidebar"
    case dock = "Dock"
    case panel = "Panels"
    case launcher = "Launcher"
    case typography = "Typography"
    case shape = "Shape and motion"
    case feedback = "Toasts"
}

/// Bereich und Einheit einer Zahl. Die Grenzen sind kein Geschmack, sondern
/// die Zusicherung, dass ein Theme die Shell nicht unbedienbar machen kann.
public struct ThemeNumberSpec: Equatable, Hashable, Sendable {
    public let unit: ThemeUnit
    public let minimum: Double
    public let maximum: Double

    public init(unit: ThemeUnit, minimum: Double, maximum: Double) {
        self.unit = unit
        self.minimum = min(minimum, maximum)
        self.maximum = max(minimum, maximum)
    }
}

/// Welcher Art ein Token ist. Der Typ entscheidet, wie der Wert gelesen wird
/// und was bei Unsinn passiert.
public enum ThemeTokenKind: Equatable, Hashable, Sendable {
    case color
    case number(ThemeNumberSpec)
    case text
    case file
    /// Aufzaehlung; die Liste steht klein geschrieben darin.
    case option([String])
    case flag

    /// Name des Typs in der Doku.
    public var label: String {
        switch self {
        case .color: "color"
        case let .number(spec):
            switch spec.unit {
            case .points: "length"
            case .ratio: "ratio"
            case .scalar: "number"
            }
        case .text: "text"
        case .file: "file"
        case .option: "option"
        case .flag: "flag"
        }
    }
}

/// Mindestkontrast einer Schriftfarbe auf einer anderen Tokenfarbe.
public struct ThemeContrastRule: Equatable, Hashable, Sendable {
    /// Name des Tokens, auf dem diese Farbe steht.
    public let background: String
    /// Kontrastverhaeltnis nach WCAG, das mindestens herauskommen muss.
    public let minimum: Double

    public init(background: String, minimum: Double) {
        self.background = background
        self.minimum = minimum
    }
}

/// Ein Token des Themes - Name, Typ, Vorgabe, Beschreibung, Gruppe.
///
/// Das Verzeichnis dieser Beschreibungen ist die einzige Wahrheit: Parser,
/// Doku und Beispiele holen alles von hier. Regeln fuer die Zukunft stehen in
/// docs/THEMES.md und werden von Tests erzwungen:
/// - Ein veroeffentlichter Name verschwindet nie.
/// - Umbenennen heisst: neuer Name, alter Name bleibt fuer immer in `aliases`.
/// - Neue Token duerfen nur dazukommen, immer mit einer Vorgabe, die dem
///   heutigen Aussehen entspricht - dann sieht ein altes Theme aus wie zuvor.
public struct ThemeTokenDescriptor: Equatable, Hashable, Sendable {
    /// `--apollo-…`, klein geschrieben.
    public let name: String
    public let kind: ThemeTokenKind
    /// Gilt, wenn das Theme nichts sagt (helles Erscheinungsbild).
    public let defaultValue: ThemeValue
    /// Vorgabe im dunklen Erscheinungsbild. Ohne eigene Angabe dieselbe wie
    /// `defaultValue` - nur Farben unterscheiden sich in der Regel.
    public let darkDefaultValue: ThemeValue
    /// Ein englischer Satz ohne Punkt, fuer Doku und Nexus.
    public let summary: String
    public let group: ThemeTokenGroup
    /// Frueher benutzte Namen. Werden weiter gelesen, fuer immer.
    public let aliases: [String]
    /// Nur fuer Schriftfarben: worauf sie steht und wie lesbar sie sein muss.
    public let contrast: ThemeContrastRule?

    public init(name: String, kind: ThemeTokenKind, defaultValue: ThemeValue,
                darkDefaultValue: ThemeValue? = nil, summary: String,
                group: ThemeTokenGroup, aliases: [String] = [],
                contrast: ThemeContrastRule? = nil) {
        self.name = name
        self.kind = kind
        self.defaultValue = defaultValue
        self.darkDefaultValue = darkDefaultValue ?? defaultValue
        self.summary = summary
        self.group = group
        self.aliases = aliases
        self.contrast = contrast
    }

    public func defaultValue(dark: Bool) -> ThemeValue {
        dark ? darkDefaultValue : defaultValue
    }

    /// Die Vorgabe so, wie man sie in eine .css-Datei schreiben wuerde.
    public func defaultText(dark: Bool = false) -> String {
        cssText(for: defaultValue(dark: dark))
    }

    /// Ein Wert dieses Tokens als CSS - fuer Doku, Beispiele und spaeter fuer
    /// den Export aus Nexus.
    public func cssText(for value: ThemeValue) -> String {
        switch value {
        case let .color(color): color.cssText
        case let .number(number):
            if case let .number(spec) = kind { spec.unit.cssText(number) } else { String(number) }
        case let .text(text): "\"\(text)\""
        case let .file(asset): asset.reference.isEmpty ? "none" : "url(\"\(asset.reference)\")"
        case let .option(option): option
        case let .flag(flag): flag ? "true" : "false"
        }
    }
}

/// Alle Token dieser Fassung. `standard` ist das Verzeichnis, mit dem die App
/// arbeitet; eigene Verzeichnisse gibt es nur in Tests.
public struct ThemeTokenCatalog: Sendable {
    public let tokens: [ThemeTokenDescriptor]
    /// Name und Aliasse, klein geschrieben, auf die Stelle in `tokens`.
    private let index: [String: Int]

    public init(_ tokens: [ThemeTokenDescriptor]) {
        self.tokens = tokens
        var index: [String: Int] = [:]
        for (position, token) in tokens.enumerated() {
            // Doppelte Namen kann es nicht geben (Test); wenn doch, gewinnt
            // der erste - lieber ein altes Token als gar keines.
            for key in ([token.name] + token.aliases).map({ $0.lowercased() }) where index[key] == nil {
                index[key] = position
            }
        }
        self.index = index
    }

    /// CSS unterscheidet bei eigenen Eigenschaften Gross- und Kleinschreibung;
    /// wir nicht. Ein Theme mit `--Apollo-Accent-Color` soll wirken statt
    /// stumm zu bleiben.
    public func descriptor(named name: String) -> ThemeTokenDescriptor? {
        index[name.lowercased()].map { tokens[$0] }
    }

    public func contains(_ name: String) -> Bool {
        descriptor(named: name) != nil
    }

    /// Vorgaben aller Token als fertige Belegung.
    public func defaults(dark: Bool) -> [String: ThemeValue] {
        var values: [String: ThemeValue] = [:]
        values.reserveCapacity(tokens.count)
        for token in tokens { values[token.name] = token.defaultValue(dark: dark) }
        return values
    }

    public static let standard = ThemeTokenCatalog(ThemeTokenCatalog.standardTokens)
}

// MARK: - Bequeme, getippte Griffe auf die Token

/// Ein Farb-Token. Die statischen Eintraege sind die Griffe fuer den Rest der
/// App: `theme.color(.accent)` kann nie den falschen Typ liefern.
public struct ThemeColorToken: Equatable, Hashable, Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
    public var descriptor: ThemeTokenDescriptor? { ThemeTokenCatalog.standard.descriptor(named: name) }
    public func defaultValue(dark: Bool = false) -> ThemeColor {
        descriptor?.defaultValue(dark: dark).color ?? .black
    }
}

public struct ThemeNumberToken: Equatable, Hashable, Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
    public var descriptor: ThemeTokenDescriptor? { ThemeTokenCatalog.standard.descriptor(named: name) }
    public func defaultValue(dark: Bool = false) -> Double {
        descriptor?.defaultValue(dark: dark).number ?? 0
    }
}

public struct ThemeTextToken: Equatable, Hashable, Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
    public var descriptor: ThemeTokenDescriptor? { ThemeTokenCatalog.standard.descriptor(named: name) }
    public func defaultValue(dark: Bool = false) -> String {
        descriptor?.defaultValue(dark: dark).text ?? ""
    }
}

public struct ThemeFileToken: Equatable, Hashable, Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
    public var descriptor: ThemeTokenDescriptor? { ThemeTokenCatalog.standard.descriptor(named: name) }
    public func defaultValue(dark: Bool = false) -> ThemeAsset {
        descriptor?.defaultValue(dark: dark).asset ?? .none
    }
}

public struct ThemeOptionToken: Equatable, Hashable, Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
    public var descriptor: ThemeTokenDescriptor? { ThemeTokenCatalog.standard.descriptor(named: name) }
    public func defaultValue(dark: Bool = false) -> String {
        descriptor?.defaultValue(dark: dark).option ?? ""
    }
}

public struct ThemeFlagToken: Equatable, Hashable, Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
    public var descriptor: ThemeTokenDescriptor? { ThemeTokenCatalog.standard.descriptor(named: name) }
    public func defaultValue(dark: Bool = false) -> Bool {
        descriptor?.defaultValue(dark: dark).flag ?? false
    }
}

public extension ThemeColorToken {
    static let background = ThemeColorToken("--apollo-background-color")
    static let surface = ThemeColorToken("--apollo-surface-color")
    static let elevatedSurface = ThemeColorToken("--apollo-elevated-surface-color")
    static let separator = ThemeColorToken("--apollo-separator-color")
    static let border = ThemeColorToken("--apollo-border-color")

    static let text = ThemeColorToken("--apollo-text-color")
    static let secondaryText = ThemeColorToken("--apollo-secondary-text-color")
    static let mutedText = ThemeColorToken("--apollo-muted-text-color")
    static let link = ThemeColorToken("--apollo-link-color")
    static let onAccent = ThemeColorToken("--apollo-on-accent-color")

    static let accent = ThemeColorToken("--apollo-accent-color")
    static let secondaryAccent = ThemeColorToken("--apollo-secondary-accent-color")
    static let selection = ThemeColorToken("--apollo-selection-color")
    static let hover = ThemeColorToken("--apollo-hover-color")
    static let success = ThemeColorToken("--apollo-success-color")
    static let warning = ThemeColorToken("--apollo-warning-color")
    static let danger = ThemeColorToken("--apollo-danger-color")

    static let bar = ThemeColorToken("--apollo-bar-color")
    static let barText = ThemeColorToken("--apollo-bar-text-color")
    static let barIcon = ThemeColorToken("--apollo-bar-icon-color")

    static let dockIndicator = ThemeColorToken("--apollo-dock-indicator-color")

    static let panel = ThemeColorToken("--apollo-panel-color")
    static let card = ThemeColorToken("--apollo-card-color")

    static let launcherHighlight = ThemeColorToken("--apollo-launcher-highlight-color")

    static let toast = ThemeColorToken("--apollo-toast-color")
    static let toastText = ThemeColorToken("--apollo-toast-text-color")
}

public extension ThemeNumberToken {
    static let format = ThemeNumberToken("--apollo-theme-format")

    static let backgroundImageOpacity = ThemeNumberToken("--apollo-background-image-opacity")
    static let surfaceOpacity = ThemeNumberToken("--apollo-surface-opacity")
    static let shadowOpacity = ThemeNumberToken("--apollo-shadow-opacity")
    static let borderWidth = ThemeNumberToken("--apollo-border-width")

    static let barWidth = ThemeNumberToken("--apollo-bar-width")
    static let barRadius = ThemeNumberToken("--apollo-bar-radius")
    static let barPadding = ThemeNumberToken("--apollo-bar-padding")
    static let barItemSpacing = ThemeNumberToken("--apollo-bar-item-spacing")
    static let barOpacity = ThemeNumberToken("--apollo-bar-opacity")
    static let barBlur = ThemeNumberToken("--apollo-bar-blur")

    static let dockIconSize = ThemeNumberToken("--apollo-dock-icon-size")
    static let dockSpacing = ThemeNumberToken("--apollo-dock-spacing")

    static let panelRadius = ThemeNumberToken("--apollo-panel-radius")
    static let panelPadding = ThemeNumberToken("--apollo-panel-padding")
    static let panelOpacity = ThemeNumberToken("--apollo-panel-opacity")
    static let panelBlur = ThemeNumberToken("--apollo-panel-blur")
    static let cardRadius = ThemeNumberToken("--apollo-card-radius")

    static let launcherRowHeight = ThemeNumberToken("--apollo-launcher-row-height")

    static let fontSize = ThemeNumberToken("--apollo-font-size")
    static let fontWeight = ThemeNumberToken("--apollo-font-weight")

    static let cornerRadius = ThemeNumberToken("--apollo-corner-radius")
    static let controlRadius = ThemeNumberToken("--apollo-control-radius")
    static let spacing = ThemeNumberToken("--apollo-spacing")
    static let animationSpeed = ThemeNumberToken("--apollo-animation-speed")

    static let toastRadius = ThemeNumberToken("--apollo-toast-radius")
}

public extension ThemeTextToken {
    static let themeName = ThemeTextToken("--apollo-theme-name")
    static let author = ThemeTextToken("--apollo-theme-author")
    static let themeDescription = ThemeTextToken("--apollo-theme-description")
    static let version = ThemeTextToken("--apollo-theme-version")
    static let homepage = ThemeTextToken("--apollo-theme-homepage")
    static let fontFamily = ThemeTextToken("--apollo-font-family")
    static let monospaceFontFamily = ThemeTextToken("--apollo-monospace-font-family")
}

public extension ThemeFileToken {
    static let authorImage = ThemeFileToken("--apollo-theme-author-image")
    static let backgroundImage = ThemeFileToken("--apollo-background-image")
}

public extension ThemeOptionToken {
    static let appearance = ThemeOptionToken("--apollo-theme-appearance")
    static let backgroundFit = ThemeOptionToken("--apollo-background-fit")
    static let iconStyle = ThemeOptionToken("--apollo-icon-style")
}

public extension ThemeFlagToken {
    static let animations = ThemeFlagToken("--apollo-animations")
    static let glass = ThemeFlagToken("--apollo-glass")
    static let shadows = ThemeFlagToken("--apollo-shadows")
}

// MARK: - Das Verzeichnis

private extension ThemeTokenDescriptor {
    static func color(_ name: String, light: UInt32, dark: UInt32? = nil,
                      alpha: Double = 1, darkAlpha: Double? = nil,
                      group: ThemeTokenGroup, _ summary: String,
                      on background: String? = nil, contrast minimum: Double = 4.5,
                      aliases: [String] = []) -> ThemeTokenDescriptor {
        ThemeTokenDescriptor(
            name: name, kind: .color,
            defaultValue: .color(ThemeColor(hex: light, alpha: alpha)),
            darkDefaultValue: .color(ThemeColor(hex: dark ?? light, alpha: darkAlpha ?? alpha)),
            summary: summary, group: group, aliases: aliases,
            contrast: background.map { ThemeContrastRule(background: $0, minimum: minimum) }
        )
    }

    static func length(_ name: String, _ value: Double, min minimum: Double = 0, max maximum: Double,
                       group: ThemeTokenGroup, _ summary: String,
                       aliases: [String] = []) -> ThemeTokenDescriptor {
        ThemeTokenDescriptor(
            name: name, kind: .number(ThemeNumberSpec(unit: .points, minimum: minimum, maximum: maximum)),
            defaultValue: .number(value), summary: summary, group: group, aliases: aliases
        )
    }

    static func ratio(_ name: String, _ value: Double, group: ThemeTokenGroup, _ summary: String,
                      dark: Double? = nil, aliases: [String] = []) -> ThemeTokenDescriptor {
        ThemeTokenDescriptor(
            name: name, kind: .number(ThemeNumberSpec(unit: .ratio, minimum: 0, maximum: 1)),
            defaultValue: .number(value), darkDefaultValue: .number(dark ?? value),
            summary: summary, group: group, aliases: aliases
        )
    }

    static func number(_ name: String, _ value: Double, min minimum: Double, max maximum: Double,
                       group: ThemeTokenGroup, _ summary: String,
                       aliases: [String] = []) -> ThemeTokenDescriptor {
        ThemeTokenDescriptor(
            name: name, kind: .number(ThemeNumberSpec(unit: .scalar, minimum: minimum, maximum: maximum)),
            defaultValue: .number(value), summary: summary, group: group, aliases: aliases
        )
    }

    static func text(_ name: String, _ value: String = "", group: ThemeTokenGroup, _ summary: String,
                     aliases: [String] = []) -> ThemeTokenDescriptor {
        ThemeTokenDescriptor(name: name, kind: .text, defaultValue: .text(value),
                             summary: summary, group: group, aliases: aliases)
    }

    static func file(_ name: String, group: ThemeTokenGroup, _ summary: String,
                     aliases: [String] = []) -> ThemeTokenDescriptor {
        ThemeTokenDescriptor(name: name, kind: .file, defaultValue: .file(.none),
                             summary: summary, group: group, aliases: aliases)
    }

    static func option(_ name: String, _ values: [String], _ value: String,
                       group: ThemeTokenGroup, _ summary: String,
                       aliases: [String] = []) -> ThemeTokenDescriptor {
        ThemeTokenDescriptor(name: name, kind: .option(values), defaultValue: .option(value),
                             summary: summary, group: group, aliases: aliases)
    }

    static func flag(_ name: String, _ value: Bool, group: ThemeTokenGroup, _ summary: String,
                     aliases: [String] = []) -> ThemeTokenDescriptor {
        ThemeTokenDescriptor(name: name, kind: .flag, defaultValue: .flag(value),
                             summary: summary, group: group, aliases: aliases)
    }
}

public extension ThemeTokenCatalog {
    /// Die Vorgaben sind das heutige Aussehen der Shell (macOS-Systemfarben,
    /// helle und dunkle Fassung). Wer nichts angibt, bekommt genau das -
    /// deshalb bleibt ein Theme von heute auch dann richtig, wenn spaeter
    /// zwanzig Token dazukommen.
    static let standardTokens: [ThemeTokenDescriptor] = [
        // MARK: Metadata
        .number("--apollo-theme-format", 1, min: 1, max: 1_000_000, group: .meta,
                "Format the theme was written for; higher numbers still load"),
        .text("--apollo-theme-name", group: .meta,
              "Name shown in the theme list; empty means the file or folder name"),
        .text("--apollo-theme-author", group: .meta, "Who made the theme"),
        .text("--apollo-theme-description", group: .meta, "One line about the theme"),
        .text("--apollo-theme-version", group: .meta, "Version of the theme itself, free text"),
        .text("--apollo-theme-homepage", group: .meta,
              "Where the theme comes from; never opened or fetched by the core"),
        .file("--apollo-theme-author-image", group: .meta,
              "Picture of the author, a file inside the theme folder"),
        .option("--apollo-theme-appearance", ["auto", "light", "dark"], "auto", group: .meta,
                "Which appearance the theme is made for; auto follows the system"),

        // MARK: Surfaces
        .color("--apollo-background-color", light: 0xE8E8ED, dark: 0x101014, group: .surface,
               "Desktop backdrop behind the shell"),
        .file("--apollo-background-image", group: .surface,
              "Image behind the shell, a file inside the theme folder"),
        .ratio("--apollo-background-image-opacity", 1, group: .surface, "How strongly the background image shows"),
        .option("--apollo-background-fit", ["fill", "fit", "stretch", "tile", "center"], "fill",
                group: .surface, "How the background image is placed"),
        .color("--apollo-surface-color", light: 0xFFFFFF, dark: 0x1C1C1E, group: .surface,
               "Base surface of windows and popovers"),
        .ratio("--apollo-surface-opacity", 1, group: .surface, "How opaque surfaces are"),
        .color("--apollo-elevated-surface-color", light: 0xF5F5F7, dark: 0x2A2A2D, group: .surface,
               "Surface of things that sit on top, such as menus"),
        .color("--apollo-separator-color", light: 0xD8D8DC, dark: 0x3A3A3D, group: .surface,
               "Hairlines between rows and sections"),
        .color("--apollo-border-color", light: 0xD0D0D4, dark: 0x3F3F43, group: .surface,
               "Outline around surfaces"),
        .length("--apollo-border-width", 1, max: 8, group: .surface, "Thickness of that outline"),
        .ratio("--apollo-shadow-opacity", 0.18, group: .surface, "How dark shadows under surfaces are", dark: 0.45),

        // MARK: Text
        .color("--apollo-text-color", light: 0x1C1C1E, dark: 0xF5F5F7, group: .text,
               "Main text", on: "--apollo-surface-color"),
        .color("--apollo-secondary-text-color", light: 0x6B6B70, dark: 0xAEAEB2, group: .text,
               "Subtitles and captions", on: "--apollo-surface-color", contrast: 3),
        .color("--apollo-muted-text-color", light: 0x8E8E93, dark: 0x8E8E93, group: .text,
               "Text that should step back, such as hints",
               on: "--apollo-surface-color", contrast: 3),
        .color("--apollo-link-color", light: 0x0060DF, dark: 0x6CB6FF, group: .text,
               "Links", on: "--apollo-surface-color"),
        .color("--apollo-on-accent-color", light: 0xFFFFFF, dark: 0xFFFFFF, group: .text,
               "Text and glyphs on accent coloured areas",
               on: "--apollo-accent-color", contrast: 3),

        // MARK: Accent and state
        .color("--apollo-accent-color", light: 0x007AFF, dark: 0x0A84FF, group: .accent,
               "Colour of selected and active things"),
        .color("--apollo-secondary-accent-color", light: 0x5E5CE6, dark: 0x7D7AFF, group: .accent,
               "Second accent for charts and badges"),
        .color("--apollo-selection-color", light: 0xD6E4FF, dark: 0x234A77, group: .accent,
               "Background of a selected row"),
        .color("--apollo-hover-color", light: 0x000000, dark: 0xFFFFFF, alpha: 0.08, darkAlpha: 0.10,
               group: .accent, "Tint under the pointer"),
        .color("--apollo-success-color", light: 0x34C759, dark: 0x30D158, group: .accent, "Everything is fine"),
        .color("--apollo-warning-color", light: 0xC77700, dark: 0xFFD60A, group: .accent, "Something needs attention"),
        .color("--apollo-danger-color", light: 0xD70015, dark: 0xFF453A, group: .accent, "Something went wrong"),

        // MARK: Sidebar
        .color("--apollo-bar-color", light: 0xF5F5F7, dark: 0x1C1C1E, group: .bar, "Backing of the sidebar"),
        .ratio("--apollo-bar-opacity", 1, group: .bar, "How opaque that backing is"),
        .color("--apollo-bar-text-color", light: 0x1C1C1E, dark: 0xF5F5F7, group: .bar,
               "Text in the sidebar, such as the clock", on: "--apollo-bar-color"),
        .color("--apollo-bar-icon-color", light: 0x3C3C43, dark: 0xE5E5EA, group: .bar,
               "Status glyphs in the sidebar", on: "--apollo-bar-color", contrast: 3),
        .length("--apollo-bar-width", 56, min: 36, max: 160, group: .bar, "Width of the sidebar"),
        .length("--apollo-bar-radius", 16, max: 48, group: .bar, "Corner radius of the sidebar"),
        .length("--apollo-bar-padding", 8, max: 48, group: .bar, "Space between sidebar edge and its blocks"),
        .length("--apollo-bar-item-spacing", 6, max: 48, group: .bar, "Space between two blocks"),
        .length("--apollo-bar-blur", 24, max: 64, group: .bar, "Blur behind the sidebar"),

        // MARK: Dock
        .length("--apollo-dock-icon-size", 32, min: 16, max: 128, group: .dock, "Size of the app icons"),
        .length("--apollo-dock-spacing", 6, max: 48, group: .dock, "Space between two app icons"),
        .color("--apollo-dock-indicator-color", light: 0x8E8E93, dark: 0xAEAEB2, group: .dock,
               "Dot under a running app"),

        // MARK: Panels
        .color("--apollo-panel-color", light: 0xFFFFFF, dark: 0x1E1E20, group: .panel,
               "Backing of dashboard, utilities and popovers"),
        .ratio("--apollo-panel-opacity", 1, group: .panel, "How opaque panels are"),
        .length("--apollo-panel-radius", 20, max: 48, group: .panel, "Corner radius of panels"),
        .length("--apollo-panel-padding", 16, max: 64, group: .panel, "Space inside a panel"),
        .length("--apollo-panel-blur", 24, max: 64, group: .panel, "Blur behind panels"),
        .color("--apollo-card-color", light: 0xF2F2F7, dark: 0x2A2A2D, group: .panel, "Backing of a card in a panel"),
        .length("--apollo-card-radius", 14, max: 48, group: .panel, "Corner radius of a card"),

        // MARK: Launcher
        .color("--apollo-launcher-highlight-color", light: 0xE5EFFF, dark: 0x2A3C55, group: .launcher,
               "Backing of the selected launcher row"),
        .length("--apollo-launcher-row-height", 40, min: 24, max: 96, group: .launcher, "Height of one launcher row"),

        // MARK: Typography
        .text("--apollo-font-family", group: .typography,
              "Font for the whole shell; empty means the system font"),
        .text("--apollo-monospace-font-family", group: .typography,
              "Font for numbers and code; empty means the system font"),
        .length("--apollo-font-size", 13, min: 8, max: 32, group: .typography, "Base text size"),
        .number("--apollo-font-weight", 400, min: 100, max: 900, group: .typography, "Base text weight"),

        // MARK: Shape and motion
        .length("--apollo-corner-radius", 12, max: 48, group: .shape, "Corner radius of everything without its own"),
        .length("--apollo-control-radius", 8, max: 48, group: .shape, "Corner radius of buttons and fields"),
        .length("--apollo-spacing", 12, max: 64, group: .shape, "Base spacing between elements"),
        .number("--apollo-animation-speed", 1, min: 0, max: 3, group: .shape,
                "Factor on every animation; 0 means no animation"),
        .flag("--apollo-animations", true, group: .shape, "Whether the shell animates at all"),
        .flag("--apollo-glass", true, group: .shape, "Whether Liquid Glass is used where it fits"),
        .flag("--apollo-shadows", true, group: .shape, "Whether surfaces cast a shadow"),
        .option("--apollo-icon-style", ["auto", "monochrome", "colorful"], "auto", group: .shape,
                "How status glyphs are drawn"),

        // MARK: Toasts
        .color("--apollo-toast-color", light: 0x1C1C1E, dark: 0xF5F5F7, group: .feedback, "Backing of a toast"),
        .color("--apollo-toast-text-color", light: 0xFFFFFF, dark: 0x1C1C1E, group: .feedback,
               "Text in a toast", on: "--apollo-toast-color"),
        .length("--apollo-toast-radius", 14, max: 48, group: .feedback, "Corner radius of a toast"),
    ]
}
