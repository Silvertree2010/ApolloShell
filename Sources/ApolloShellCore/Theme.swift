import Foundation

public enum ThemeFormat {
    public static let current = 1
}

public extension ThemeTokenCatalog {
    static let prefix = "--apollo-"
}

public struct Theme: Equatable, Sendable {
    public let identifier: String
    public let slug: String
    public let formatVersion: Int
    public let issues: [ThemeIssue]
    public let lightValues: [String: ThemeValue]
    public let darkValues: [String: ThemeValue]
    public let icons: ThemeIconSet
    public let foreignLightValues: [String: String]
    public let foreignDarkValues: [String: String]

    init(identifier: String, formatVersion: Int, issues: [ThemeIssue],
         lightValues: [String: ThemeValue], darkValues: [String: ThemeValue],
         icons: ThemeIconSet = .none,
         foreignLightValues: [String: String] = [:], foreignDarkValues: [String: String] = [:]) {
        let name = Theme.cleanIdentifier(identifier)
        self.identifier = name
        slug = Theme.slug(from: name)
        self.formatVersion = formatVersion
        self.issues = issues
        self.lightValues = lightValues
        self.darkValues = darkValues
        self.icons = icons
        self.foreignLightValues = foreignLightValues
        self.foreignDarkValues = foreignDarkValues
    }

    public static let standard = Theme.make(identifier: "default", styleSheet: ThemeStyleSheet())

    public func value(_ name: String, dark: Bool = false) -> ThemeValue? {
        (dark ? darkValues : lightValues)[name.lowercased()]
    }

    public func value<Kind>(_ token: ThemeToken<Kind>, dark: Bool = false) -> Kind.Value? {
        value(token.name, dark: dark).flatMap(Kind.value(from:))
    }

    public func declares(_ name: String) -> Bool {
        value(name) != nil || value(name, dark: true) != nil
    }

    public func file(_ token: ThemeFileToken, dark: Bool = false) -> URL? {
        value(token, dark: dark)?.url
    }

    public func readableColor(_ token: ThemeColorToken, dark: Bool = false) -> ThemeColor? {
        if let color = value(token, dark: dark) { return color }
        guard let rule = token.descriptor?.contrast,
              let background = value(rule.background, dark: dark)?.color
        else { return nil }
        return ThemeGuards.readable(token.defaultValue(dark: dark), on: background, minimum: rule.minimum)
    }

    public func icon(_ id: String) -> URL? {
        icons.file(id)
    }

    public var title: String {
        let name = value(ThemeTextToken.themeName) ?? ""
        return name.isEmpty ? identifier : name
    }

    public var author: String { value(ThemeTextToken.author) ?? "" }
    public var details: String { value(ThemeTextToken.themeDescription) ?? "" }

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
        let foreignLight = foreignValues(styleSheet.light, limits: limits)
        let foreignDark = foreignLight.merging(foreignValues(styleSheet.dark, limits: limits)) { _, new in new }
        return Theme(identifier: identifier, formatVersion: format,
                     issues: withoutDuplicates(log.finished()),
                     lightValues: lightValues, darkValues: darkValues, icons: icons,
                     foreignLightValues: foreignLight, foreignDarkValues: foreignDark)
    }

    private static func foreignValues(_ declarations: [ThemeDeclaration], limits: ThemeLimits) -> [String: String] {
        var values: [String: String] = [:]
        for declaration in declarations where !declaration.name.hasPrefix(ThemeTokenCatalog.prefix) {
            var text = declaration.value
            if let range = text.range(of: "!important", options: [.caseInsensitive, .backwards]),
               range.upperBound == text.endIndex {
                text = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let lowered = text.lowercased()
            guard !text.isEmpty, text.count <= limits.maxTextLength,
                  !lowered.contains("var("), !lowered.contains("url("),
                  !text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
            else { continue }
            values[declaration.name] = text
        }
        return values
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

public enum ThemeGuards {
    static func enforceContrast(in values: inout [String: ThemeValue],
                                catalog: ThemeTokenCatalog,
                                dark: Bool,
                                log: inout ThemeIssueLog) {
        for token in catalog.tokens {
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

    public static func readable(_ color: ThemeColor, on background: ThemeColor, minimum: Double) -> ThemeColor {
        let base = background.alpha < 1 ? background.withAlpha(1) : background
        func ratio(_ candidate: ThemeColor) -> Double {
            ThemeColor.contrast(candidate.composited(over: base), base)
        }
        guard minimum > 1, ratio(color) < minimum else { return color }
        let target: ThemeColor = ThemeColor.contrast(.black, base) >= ThemeColor.contrast(.white, base)
            ? .black : .white
        var amount = 0.0
        while amount < 1 {
            amount = min(amount + 0.02, 1)
            let candidate = color.blended(with: target, amount: amount)
            if ratio(candidate) >= minimum { return candidate }
        }
        return ThemeColor.contrast(.white, base) >= ThemeColor.contrast(.black, base) ? .white : .black
    }
}

public enum ThemeAppearance: String, Sendable {
    case auto, light, dark

    public init(theme: Theme) {
        let raw = theme.value(.appearance) ?? theme.value(.appearance, dark: true)
        self = raw.flatMap { ThemeAppearance(rawValue: $0.lowercased()) } ?? .auto
    }
}
