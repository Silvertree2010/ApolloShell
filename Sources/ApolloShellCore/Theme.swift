import Foundation

/// The format number this version of the app understands.
///
/// A theme names it in `--apollo-theme-format`. If it names a higher one,
/// it is still loaded: what this version understands is read, unknown
/// tokens are skipped and reported as a hint. It is never rejected -
/// otherwise a theme from the future would be unusable instead of merely
/// looking different. The number only increases when the meaning of an
/// existing token changes; tokens being added does not change it.
public enum ThemeFormat {
    public static let current = 1
}

public extension ThemeTokenCatalog {
    /// Only names with this prefix belong to us. Everything else
    /// (`--my-blue`) is the namespace of whoever writes the theme, and is
    /// silently passed over.
    static let prefix = "--apollo-"
}

/// A fully read theme: the values in the file, light and dark, already
/// clamped and checked for readability.
///
/// There is no way to get an unchecked value. What the file does not name
/// is also missing here (`nil`) - "what you don't set stays as it is":
/// the defaults in the directory only approximate the shell's look,
/// anyone who applied one did in fact change something (say, the width of
/// the bar). The app chooses the fallback, usually the system color of
/// macOS.
public struct Theme: Equatable, Sendable {
    /// Folder or file name without `.css`. Stays the same as long as the
    /// file is named the same - the "which theme" setting and the entry
    /// on the website will later depend on it.
    public let identifier: String
    /// Lowercased version of the identifier for URLs and file names.
    public let slug: String
    /// What was stated in `--apollo-theme-format`.
    public let formatVersion: Int
    /// Everything noticed while reading. Never a reason not to use the
    /// theme.
    public let issues: [ThemeIssue]
    /// Only the named tokens. Light: what is in `:root`; dark: plus what
    /// the `@media` block overrides or adds.
    public let lightValues: [String: ThemeValue]
    public let darkValues: [String: ThemeValue]
    /// The images from `icons/`, if the theme is a folder.
    public let icons: ThemeIconSet

    init(identifier: String, formatVersion: Int, issues: [ThemeIssue],
         lightValues: [String: ThemeValue], darkValues: [String: ThemeValue],
         icons: ThemeIconSet = .none) {
        let name = Theme.cleanIdentifier(identifier)
        self.identifier = name
        slug = Theme.slug(from: name)
        self.formatVersion = formatVersion
        self.issues = issues
        self.lightValues = lightValues
        self.darkValues = darkValues
        self.icons = icons
    }

    /// The built-in look: no value, no hint - the shell as it looks
    /// without a theme. Also the fallback when a file is unusable.
    public static let standard = Theme.make(identifier: "default", styleSheet: ThemeStyleSheet())

    // MARK: - Reading values

    public func value(_ name: String, dark: Bool = false) -> ThemeValue? {
        (dark ? darkValues : lightValues)[name.lowercased()]
    }

    /// The value of a token as the file names it - `nil` if it does not
    /// name it in this appearance.
    public func value<Kind>(_ token: ThemeToken<Kind>, dark: Bool = false) -> Kind.Value? {
        value(token.name, dark: dark).flatMap(Kind.value(from:))
    }

    /// Does the theme name this token at all (light or dark)?
    public func declares(_ name: String) -> Bool {
        value(name) != nil || value(name, dark: true) != nil
    }

    /// The validated file - `nil` if none was specified or it may not be
    /// used.
    public func file(_ token: ThemeFileToken, dark: Bool = false) -> URL? {
        value(token, dark: dark)?.url
    }

    /// A text color, even if the theme only names its background: then
    /// the default, shifted as far as necessary to be readable on it. If
    /// it names neither the color nor the background: `nil`, the app
    /// stays with the macOS color - which then matches macOS's
    /// background anyway.
    public func readableColor(_ token: ThemeColorToken, dark: Bool = false) -> ThemeColor? {
        if let color = value(token, dark: dark) { return color }
        guard let rule = token.descriptor?.contrast,
              let background = value(rule.background, dark: dark)?.color
        else { return nil }
        return ThemeGuards.readable(token.defaultValue(dark: dark), on: background, minimum: rule.minimum)
    }

    /// The image this theme brings for a symbol - `nil` if none is
    /// included. Then the built-in SF Symbol applies.
    public func icon(_ id: String) -> URL? {
        icons.file(id)
    }

    /// What appears in the list: the name from the theme, otherwise the
    /// identifier.
    public var title: String {
        let name = value(ThemeTextToken.themeName) ?? ""
        return name.isEmpty ? identifier : name
    }

    public var author: String { value(ThemeTextToken.author) ?? "" }
    public var details: String { value(ThemeTextToken.themeDescription) ?? "" }

    // MARK: - Building

    /// Build a theme from parsed declarations. Cannot fail.
    ///
    /// The declarations from `:root` apply in both appearances; the
    /// `@media` block only layers on top - as in CSS. What is missing
    /// stays empty; only the contrast check then measures against the
    /// background from the directory.
    public static func make(identifier: String,
                            styleSheet: ThemeStyleSheet,
                            assets: ThemeAssetResolver = .none,
                            catalog: ThemeTokenCatalog = .standard,
                            limits: ThemeLimits = .standard,
                            issues: [ThemeIssue] = [],
                            icons: ThemeIconSet = .none) -> Theme {
        var log = ThemeIssueLog(limit: limits.maxIssues)
        log.append(contentsOf: issues)
        log.append(contentsOf: styleSheet.issues)
        var cache: [String: ThemeAssetOutcome] = [:]
        let light = apply(styleSheet.light, catalog: catalog, limits: limits,
                          assets: assets, cache: &cache, log: &log)
        let dark = apply(styleSheet.dark, catalog: catalog, limits: limits,
                         assets: assets, cache: &cache, log: &log)
        var lightValues = light
        var darkValues = light.merging(dark) { _, new in new }
        ThemeGuards.enforceContrast(in: &lightValues, catalog: catalog, dark: false, log: &log)
        ThemeGuards.enforceContrast(in: &darkValues, catalog: catalog, dark: true, log: &log)
        let format = Int(lightValues[ThemeNumberToken.format.name]?.number ?? Double(ThemeFormat.current))
        if format > ThemeFormat.current {
            log.add(.newerFormat(found: format, known: ThemeFormat.current))
        }
        return Theme(identifier: identifier, formatVersion: format,
                     issues: withoutDuplicates(log.finished()),
                     lightValues: lightValues, darkValues: darkValues, icons: icons)
    }

    private static func apply(_ declarations: [ThemeDeclaration],
                              catalog: ThemeTokenCatalog,
                              limits: ThemeLimits,
                              assets: ThemeAssetResolver,
                              cache: inout [String: ThemeAssetOutcome],
                              log: inout ThemeIssueLog) -> [String: ThemeValue] {
        var values: [String: ThemeValue] = [:]
        for declaration in declarations {
            guard let token = catalog.descriptor(named: declaration.name) else {
                // Unknown usually means: the theme is newer than the app,
                // or someone made a typo. Either way just a hint.
                if declaration.name.hasPrefix(ThemeTokenCatalog.prefix) {
                    log.add(.unknownToken(declaration.name), line: declaration.line)
                }
                continue
            }
            guard var value = ThemeValueReader.read(declaration.value, kind: token.kind) else {
                log.add(.unreadableValue(token: token.name, value: shortened(declaration.value)),
                        line: declaration.line)
                continue
            }
            if case let .number(spec) = token.kind, case let .number(raw) = value {
                let clamped = min(max(raw, spec.minimum), spec.maximum)
                if clamped != raw {
                    log.add(.clamped(token: token.name,
                                     value: spec.unit.cssText(raw),
                                     used: spec.unit.cssText(clamped)),
                            line: declaration.line)
                    value = .number(clamped)
                }
            }
            if case .text = token.kind, case let .text(raw) = value, raw.count > limits.maxTextLength {
                log.add(.clamped(token: token.name,
                                 value: "\(raw.count) characters",
                                 used: "\(limits.maxTextLength) characters"),
                        line: declaration.line)
                value = .text(String(raw.prefix(limits.maxTextLength)))
            }
            if case let .file(asset) = value {
                guard !asset.reference.isEmpty else {
                    values[token.name] = .file(.none)
                    continue
                }
                let outcome = cache[asset.reference] ?? assets(asset.reference)
                cache[asset.reference] = outcome
                switch outcome {
                case let .success(url):
                    value = .file(ThemeAsset(reference: asset.reference, url: url))
                case let .failure(reason):
                    log.add(.rejectedAsset(reference: shortened(asset.reference), reason: reason),
                            line: declaration.line)
                    continue
                }
            }
            values[token.name] = value
        }
        return values
    }

    /// A hint that quotes text from the file must not blow up the display.
    private static func shortened(_ text: String) -> String {
        text.count <= 60 ? text : String(text.prefix(60)) + "…"
    }

    private static func withoutDuplicates(_ issues: [ThemeIssue]) -> [ThemeIssue] {
        var seen: Set<ThemeIssue> = []
        return issues.filter { seen.insert($0).inserted }
    }

    private static func cleanIdentifier(_ raw: String) -> String {
        var name = raw.trimmedText
        while name.hasPrefix(".") { name.removeFirst() }
        name = String(name.prefix(120))
        return name.isEmpty ? "theme" : name
    }

    /// ASCII only: the short name should later be able to appear in a URL
    /// and in a file name without anyone having to think about encoding.
    private static func slug(from name: String) -> String {
        var result = ""
        for character in name.lowercased() {
            if character.isASCII, character.isLetter || character.isNumber {
                result.append(character)
            } else if !result.hasSuffix("-") {
                result.append("-")
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        while result.hasPrefix("-") { result.removeFirst() }
        return result.isEmpty ? "theme" : result
    }
}

/// The limits a theme cannot exceed.
///
/// Numbers are already clamped to the token's range by `Theme.apply`.
/// What is here is what only emerges from the interplay: a text color
/// that would not be readable on its background is lightened or darkened
/// until it is. A theme therefore cannot blind the shell - neither by
/// accident nor on purpose.
public enum ThemeGuards {
    static func enforceContrast(in values: inout [String: ThemeValue],
                                catalog: ThemeTokenCatalog,
                                dark: Bool,
                                log: inout ThemeIssueLog) {
        // Via the catalog instead of via the dictionary: the order of
        // hints should always be the same for the same file.
        for token in catalog.tokens {
            // If the theme does not name the background, the text sits on
            // the shell's - which the default in the directory
            // approximates.
            guard let rule = token.contrast,
                  let color = values[token.name]?.color,
                  let background = values[rule.background]?.color
                      ?? catalog.descriptor(named: rule.background)?.defaultValue(dark: dark).color
            else { continue }
            let fixed = readable(color, on: background, minimum: rule.minimum)
            guard fixed != color else { continue }
            log.add(.contrastAdjusted(token: token.name, requested: color.cssText,
                                      used: fixed.cssText, dark: dark))
            values[token.name] = .color(fixed)
        }
    }

    /// `color` shifted toward black or white until the contrast against
    /// `background` is sufficient. Colors that are already readable stay
    /// exactly as they are.
    public static func readable(_ color: ThemeColor, on background: ThemeColor, minimum: Double) -> ThemeColor {
        // The background's opacity does not matter here: what lies behind
        // it, the theme does not know.
        let base = background.alpha < 1 ? background.withAlpha(1) : background
        func ratio(_ candidate: ThemeColor) -> Double {
            ThemeColor.contrast(candidate.composited(over: base), base)
        }
        guard minimum > 1, ratio(color) < minimum else { return color }
        // The direction in which more contrast can even be gained. Black
        // and white gain the same only around a brightness of 0.18, not
        // at 0.5: on a medium-bright background only black reaches the
        // target.
        let target: ThemeColor = ThemeColor.contrast(.black, base) >= ThemeColor.contrast(.white, base)
            ? .black : .white
        var amount = 0.0
        while amount < 1 {
            amount = min(amount + 0.02, 1)
            let candidate = color.blended(with: target, amount: amount)
            if ratio(candidate) >= minimum { return candidate }
        }
        // Even pure black or white is not enough (medium-gray background
        // or transparent text): then opaque and in the direction that
        // gains more.
        return ThemeColor.contrast(.white, base) >= ThemeColor.contrast(.black, base) ? .white : .black
    }
}

// MARK: - Appearance

/// Which appearance a theme is made for (`--apollo-theme-appearance`).
/// `light`/`dark` set the whole shell to it, independent of macOS -
/// otherwise a light theme on a dark Mac would get white system text on
/// light surfaces. `auto` (and none or an unknown value) follows the
/// system as before.
public enum ThemeAppearance: String, Sendable {
    case auto, light, dark

    public init(theme: Theme) {
        let raw = theme.value(.appearance) ?? theme.value(.appearance, dark: true)
        self = raw.flatMap { ThemeAppearance(rawValue: $0.lowercased()) } ?? .auto
    }
}
