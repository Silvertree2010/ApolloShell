import Foundation

/// What a token belongs to. Only for grouping in the docs and later in Nexus
/// - the membership may change, the name never.
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

/// The range and the unit of a number. The limits are no taste but the
/// promise that a theme cannot make the shell unusable.
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

/// Which kind a token is. The type decides how the value is read and what
/// happens with nonsense.
public enum ThemeTokenKind: Equatable, Hashable, Sendable {
    case color
    /// A gradient or `none`; see `ThemeGradient`.
    case gradient
    case number(ThemeNumberSpec)
    case text
    case file
    /// An enumeration; the list stands in it in lower case.
    case option([String])
    case flag

    /// The name of the type in the docs.
    public var label: String {
        switch self {
        case .color: "color"
        case .gradient: "gradient"
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

/// The minimum contrast of a text color on another token color.
public struct ThemeContrastRule: Equatable, Hashable, Sendable {
    /// The name of the token this color stands on.
    public let background: String
    /// The contrast ratio per WCAG that has to come out at least.
    public let minimum: Double

    public init(background: String, minimum: Double) {
        self.background = background
        self.minimum = minimum
    }
}

/// A token of the theme - name, type, default, description, group.
///
/// The catalogue of these descriptions is the single truth: the parser, the
/// docs and the examples take everything from here. The rules for the future
/// stand in docs/THEMES.md and are enforced by tests:
/// - A published name never disappears.
/// - Renaming means: a new name, and the old one stays in `aliases` forever.
/// - New tokens may only be added, always with a default that matches how it
///   looks today - then an old theme looks the way it did.
public struct ThemeTokenDescriptor: Equatable, Hashable, Sendable {
    /// `--apollo-…`, in lower case.
    public let name: String
    public let kind: ThemeTokenKind
    /// Holds when the theme says nothing (light appearance).
    public let defaultValue: ThemeValue
    /// The default in the dark appearance. Without an entry of its own the
    /// same as `defaultValue` - as a rule only colors differ.
    public let darkDefaultValue: ThemeValue
    /// An English sentence without a full stop, for the docs and Nexus.
    public let summary: String
    public let group: ThemeTokenGroup
    /// Names used earlier. They go on being read, forever.
    public let aliases: [String]
    /// Only for text colors: what it stands on and how readable it has to be.
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

    /// The default the way one would write it into a .css file.
    public func defaultText(dark: Bool = false) -> String {
        cssText(for: defaultValue(dark: dark))
    }

    /// A value of this token as CSS - for the docs, the examples and later for
    /// the export out of Nexus.
    public func cssText(for value: ThemeValue) -> String {
        switch value {
        case let .color(color): color.cssText
        case let .gradient(gradient): gradient.cssText
        case let .number(number):
            if case let .number(spec) = kind { spec.unit.cssText(number) } else { String(number) }
        case let .text(text): "\"\(text)\""
        case let .file(asset): asset.reference.isEmpty ? "none" : "url(\"\(asset.reference)\")"
        case let .option(option): option
        case let .flag(flag): flag ? "true" : "false"
        }
    }
}

/// All tokens of this version. `standard` is the catalogue the app works
/// with; catalogues of one's own only exist in tests.
public struct ThemeTokenCatalog: Sendable {
    public let tokens: [ThemeTokenDescriptor]
    /// The name and the aliases, in lower case, onto the place in `tokens`.
    private let index: [String: Int]

    public init(_ tokens: [ThemeTokenDescriptor]) {
        self.tokens = tokens
        var index: [String: Int] = [:]
        for (position, token) in tokens.enumerated() {
            // There can be no duplicate names (a test); should there be, the
            // first one wins - an old token rather than none at all.
            for key in ([token.name] + token.aliases).map({ $0.lowercased() }) where index[key] == nil {
                index[key] = position
            }
        }
        self.index = index
    }

    /// CSS tells upper and lower case apart in custom properties; we do not. A
    /// theme with `--Apollo-Accent-Color` should take hold instead of staying
    /// silent.
    public func descriptor(named name: String) -> ThemeTokenDescriptor? {
        index[name.lowercased()].map { tokens[$0] }
    }

    public func contains(_ name: String) -> Bool {
        descriptor(named: name) != nil
    }

    /// The defaults of all tokens as a finished set.
    public func defaults(dark: Bool) -> [String: ThemeValue] {
        var values: [String: ThemeValue] = [:]
        values.reserveCapacity(tokens.count)
        for token in tokens { values[token.name] = token.defaultValue(dark: dark) }
        return values
    }

    public static let standard = ThemeTokenCatalog(ThemeTokenCatalog.standardTokens)
}

// MARK: - Convenient, typed handles on the tokens

/// Which kind of value a token carries, as a type: that way `theme.value(.accent)`
/// can never hand back the wrong type. The kinds themselves stand in `ThemeTokenTypes`.
public protocol ThemeTokenType: Sendable {
    associatedtype Value: Equatable & Sendable
    /// The value when the value that was read is of this kind.
    static func value(from value: ThemeValue) -> Value?
    /// Only in case a token is missing in the catalogue (a test prevents that).
    static var fallback: Value { get }
}

public enum ThemeTokenTypes {
    public enum Color: ThemeTokenType {
        public static func value(from value: ThemeValue) -> ThemeColor? { value.color }
        public static var fallback: ThemeColor { .black }
    }

    /// `none` means: the color next to it colors the area.
    public enum Gradient: ThemeTokenType {
        public static func value(from value: ThemeValue) -> ThemeGradient? { value.gradient }
        public static var fallback: ThemeGradient { .none }
    }

    public enum Number: ThemeTokenType {
        public static func value(from value: ThemeValue) -> Double? { value.number }
        public static var fallback: Double { 0 }
    }

    public enum Text: ThemeTokenType {
        public static func value(from value: ThemeValue) -> String? { value.text }
        public static var fallback: String { "" }
    }

    public enum File: ThemeTokenType {
        public static func value(from value: ThemeValue) -> ThemeAsset? { value.asset }
        public static var fallback: ThemeAsset { .none }
    }

    public enum Option: ThemeTokenType {
        public static func value(from value: ThemeValue) -> String? { value.option }
        public static var fallback: String { "" }
    }

    public enum Flag: ThemeTokenType {
        public static func value(from value: ThemeValue) -> Bool? { value.flag }
        public static var fallback: Bool { false }
    }
}

/// A handle on a token. The static entries below are the handles for the rest
/// of the app.
public struct ThemeToken<Kind: ThemeTokenType>: Equatable, Hashable, Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
    public var descriptor: ThemeTokenDescriptor? { ThemeTokenCatalog.standard.descriptor(named: name) }

    /// The default out of the catalogue. Only for the docs, the examples and
    /// as the ground of the contrast check - the shell itself takes what the
    /// theme does not name from macOS (see `Theme.value`).
    public func defaultValue(dark: Bool = false) -> Kind.Value {
        descriptor.flatMap { Kind.value(from: $0.defaultValue(dark: dark)) } ?? Kind.fallback
    }
}

public typealias ThemeColorToken = ThemeToken<ThemeTokenTypes.Color>
public typealias ThemeGradientToken = ThemeToken<ThemeTokenTypes.Gradient>
public typealias ThemeNumberToken = ThemeToken<ThemeTokenTypes.Number>
public typealias ThemeTextToken = ThemeToken<ThemeTokenTypes.Text>
public typealias ThemeFileToken = ThemeToken<ThemeTokenTypes.File>
public typealias ThemeOptionToken = ThemeToken<ThemeTokenTypes.Option>
public typealias ThemeFlagToken = ThemeToken<ThemeTokenTypes.Flag>

public extension ThemeToken where Kind == ThemeTokenTypes.Gradient {
    static var background: Self { Self("--apollo-background-gradient") }
    static var surface: Self { Self("--apollo-surface-gradient") }
    static var accent: Self { Self("--apollo-accent-gradient") }
    static var bar: Self { Self("--apollo-bar-gradient") }
    static var panel: Self { Self("--apollo-panel-gradient") }
    static var card: Self { Self("--apollo-card-gradient") }
    static var launcherHighlight: Self { Self("--apollo-launcher-highlight-gradient") }
    static var toast: Self { Self("--apollo-toast-gradient") }
}

public extension ThemeToken where Kind == ThemeTokenTypes.Color {
    static var background: Self { Self("--apollo-background-color") }
    static var surface: Self { Self("--apollo-surface-color") }
    static var elevatedSurface: Self { Self("--apollo-elevated-surface-color") }
    static var separator: Self { Self("--apollo-separator-color") }
    static var border: Self { Self("--apollo-border-color") }

    static var text: Self { Self("--apollo-text-color") }
    static var secondaryText: Self { Self("--apollo-secondary-text-color") }
    static var mutedText: Self { Self("--apollo-muted-text-color") }
    static var link: Self { Self("--apollo-link-color") }
    static var onAccent: Self { Self("--apollo-on-accent-color") }

    static var accent: Self { Self("--apollo-accent-color") }
    static var secondaryAccent: Self { Self("--apollo-secondary-accent-color") }
    static var selection: Self { Self("--apollo-selection-color") }
    static var hover: Self { Self("--apollo-hover-color") }
    static var success: Self { Self("--apollo-success-color") }
    static var warning: Self { Self("--apollo-warning-color") }
    static var danger: Self { Self("--apollo-danger-color") }

    static var bar: Self { Self("--apollo-bar-color") }
    static var barText: Self { Self("--apollo-bar-text-color") }
    static var barIcon: Self { Self("--apollo-bar-icon-color") }

    static var dockIndicator: Self { Self("--apollo-dock-indicator-color") }

    static var panel: Self { Self("--apollo-panel-color") }
    static var card: Self { Self("--apollo-card-color") }

    static var launcherHighlight: Self { Self("--apollo-launcher-highlight-color") }

    static var toast: Self { Self("--apollo-toast-color") }
    static var toastText: Self { Self("--apollo-toast-text-color") }
}

public extension ThemeToken where Kind == ThemeTokenTypes.Number {
    static var format: Self { Self("--apollo-theme-format") }

    static var backgroundImageOpacity: Self { Self("--apollo-background-image-opacity") }
    static var surfaceOpacity: Self { Self("--apollo-surface-opacity") }
    static var shadowOpacity: Self { Self("--apollo-shadow-opacity") }
    static var borderWidth: Self { Self("--apollo-border-width") }

    static var barWidth: Self { Self("--apollo-bar-width") }
    static var barRadius: Self { Self("--apollo-bar-radius") }
    static var barPadding: Self { Self("--apollo-bar-padding") }
    static var barItemSpacing: Self { Self("--apollo-bar-item-spacing") }
    static var barOpacity: Self { Self("--apollo-bar-opacity") }
    static var barBlur: Self { Self("--apollo-bar-blur") }

    static var dockIconSize: Self { Self("--apollo-dock-icon-size") }
    static var dockSpacing: Self { Self("--apollo-dock-spacing") }

    static var panelRadius: Self { Self("--apollo-panel-radius") }
    static var panelPadding: Self { Self("--apollo-panel-padding") }
    static var panelOpacity: Self { Self("--apollo-panel-opacity") }
    static var panelBlur: Self { Self("--apollo-panel-blur") }
    static var cardRadius: Self { Self("--apollo-card-radius") }

    static var launcherRowHeight: Self { Self("--apollo-launcher-row-height") }

    static var fontSize: Self { Self("--apollo-font-size") }
    static var fontWeight: Self { Self("--apollo-font-weight") }

    static var cornerRadius: Self { Self("--apollo-corner-radius") }
    static var controlRadius: Self { Self("--apollo-control-radius") }
    static var spacing: Self { Self("--apollo-spacing") }
    static var animationSpeed: Self { Self("--apollo-animation-speed") }

    static var toastRadius: Self { Self("--apollo-toast-radius") }
}

public extension ThemeToken where Kind == ThemeTokenTypes.Text {
    static var themeName: Self { Self("--apollo-theme-name") }
    static var author: Self { Self("--apollo-theme-author") }
    static var themeDescription: Self { Self("--apollo-theme-description") }
    static var version: Self { Self("--apollo-theme-version") }
    static var homepage: Self { Self("--apollo-theme-homepage") }
    static var fontFamily: Self { Self("--apollo-font-family") }
    static var monospaceFontFamily: Self { Self("--apollo-monospace-font-family") }
}

public extension ThemeToken where Kind == ThemeTokenTypes.File {
    static var authorImage: Self { Self("--apollo-theme-author-image") }
    static var backgroundImage: Self { Self("--apollo-background-image") }
}

public extension ThemeToken where Kind == ThemeTokenTypes.Option {
    static var appearance: Self { Self("--apollo-theme-appearance") }
    static var backgroundFit: Self { Self("--apollo-background-fit") }
    static var iconStyle: Self { Self("--apollo-icon-style") }
}

public extension ThemeToken where Kind == ThemeTokenTypes.Flag {
    static var animations: Self { Self("--apollo-animations") }
    static var glass: Self { Self("--apollo-glass") }
    static var shadows: Self { Self("--apollo-shadows") }
}

// MARK: - The catalogue

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

    /// A gradient token. The default is always `none`: that way a theme of
    /// today looks exactly as it did, and a gradient is something somebody
    /// asks for on purpose.
    static func gradient(_ name: String, group: ThemeTokenGroup, _ summary: String,
                         aliases: [String] = []) -> ThemeTokenDescriptor {
        ThemeTokenDescriptor(name: name, kind: .gradient, defaultValue: .gradient(.none),
                             summary: summary, group: group, aliases: aliases)
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
    /// The defaults are how the shell looks today (macOS system colors, a
    /// light and a dark version). Whoever names nothing gets exactly that -
    /// so a theme of today stays right even when twenty tokens are added
    /// later.
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
        .gradient("--apollo-background-gradient", group: .surface,
                  "Gradient behind the shell instead of the flat backdrop colour"),
        .gradient("--apollo-surface-gradient", group: .surface,
                  "Gradient across surfaces instead of the flat surface colour"),
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
        .gradient("--apollo-accent-gradient", group: .accent,
                  "Gradient for accent coloured areas instead of the flat accent colour"),
        .color("--apollo-selection-color", light: 0xD6E4FF, dark: 0x234A77, group: .accent,
               "Background of a selected row"),
        .color("--apollo-hover-color", light: 0x000000, dark: 0xFFFFFF, alpha: 0.08, darkAlpha: 0.10,
               group: .accent, "Tint under the pointer"),
        .color("--apollo-success-color", light: 0x34C759, dark: 0x30D158, group: .accent, "Everything is fine"),
        .color("--apollo-warning-color", light: 0xC77700, dark: 0xFFD60A, group: .accent, "Something needs attention"),
        .color("--apollo-danger-color", light: 0xD70015, dark: 0xFF453A, group: .accent, "Something went wrong"),

        // MARK: Sidebar
        .color("--apollo-bar-color", light: 0xF5F5F7, dark: 0x1C1C1E, group: .bar, "Backing of the sidebar"),
        .gradient("--apollo-bar-gradient", group: .bar,
                  "Gradient along the sidebar instead of the flat bar colour"),
        .ratio("--apollo-bar-opacity", 1, group: .bar, "How opaque that backing is"),
        .color("--apollo-bar-text-color", light: 0x1C1C1E, dark: 0xF5F5F7, group: .bar,
               "Text in the sidebar, such as the clock", on: "--apollo-bar-color"),
        .color("--apollo-bar-icon-color", light: 0x3C3C43, dark: 0xE5E5EA, group: .bar,
               "Status glyphs in the sidebar", on: "--apollo-bar-color", contrast: 3),
        .length("--apollo-bar-width", 44, min: 36, max: 160, group: .bar, "Width of the sidebar"),
        .length("--apollo-bar-radius", 16, max: 48, group: .bar, "Corner radius of the sidebar"),
        .length("--apollo-bar-padding", 10, max: 48, group: .bar, "Space between sidebar edge and its blocks"),
        .length("--apollo-bar-item-spacing", 8, max: 48, group: .bar, "Space between two blocks"),
        .length("--apollo-bar-blur", 24, max: 64, group: .bar, "Blur behind the sidebar"),

        // MARK: Dock
        .length("--apollo-dock-icon-size", 26, min: 16, max: 128, group: .dock, "Size of the app icons"),
        .length("--apollo-dock-spacing", 4, max: 48, group: .dock, "Space between two app icons"),
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
        .gradient("--apollo-panel-gradient", group: .panel,
                  "Gradient across a panel instead of the flat panel colour"),
        .gradient("--apollo-card-gradient", group: .panel,
                  "Gradient across a card instead of the flat card colour"),
        .length("--apollo-card-radius", 14, max: 48, group: .panel, "Corner radius of a card"),

        // MARK: Launcher
        .color("--apollo-launcher-highlight-color", light: 0xE5EFFF, dark: 0x2A3C55, group: .launcher,
               "Backing of the selected launcher row"),
        .gradient("--apollo-launcher-highlight-gradient", group: .launcher,
                  "Gradient behind the selected launcher row instead of the flat colour"),
        .length("--apollo-launcher-row-height", 44, min: 24, max: 96, group: .launcher, "Height of one launcher row"),

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
        .gradient("--apollo-toast-gradient", group: .feedback,
                  "Gradient across a toast instead of the flat toast colour"),
        .color("--apollo-toast-text-color", light: 0xFFFFFF, dark: 0x1C1C1E, group: .feedback,
               "Text in a toast", on: "--apollo-toast-color"),
        .length("--apollo-toast-radius", 14, max: 48, group: .feedback, "Corner radius of a toast"),
    ]
}
