import Foundation

/// Why a theme cannot go to the Marketplace as it is.
public enum ThemeCanonicalProblem: Error, Equatable, Sendable {
    /// The theme points at a file (a background, an author picture). The
    /// Marketplace takes plain CSS only for now.
    case usesFiles([String])
    /// Nothing the shell knows about is left.
    case noTokens
}

/// Writes a theme back out as CSS in one fixed form: only tokens the shell
/// knows, values as the shell read them, in catalogue order, no comments.
///
/// This is what goes to the Marketplace. The server takes this form and
/// nothing else (it checks every line against the token manifest), so a
/// file that looked fine to the parser but carried anything else - a
/// selector, an `@import`, a stray comment - never reaches another Mac.
public enum ThemeCanonical {
    /// Tokens the Marketplace drops: the author comes from the GitHub
    /// account, a homepage would be a link nobody checked, and the format
    /// is written by whoever writes the file.
    public static let droppedTokens: Set<String> = [
        "--apollo-theme-author",
        "--apollo-theme-homepage",
        "--apollo-theme-format",
    ]

    public static func css(for theme: Theme,
                           catalog: ThemeTokenCatalog = .standard) -> Result<String, ThemeCanonicalProblem> {
        var files: [String] = []
        var light: [String] = []
        var dark: [String] = []
        for token in catalog.tokens where !droppedTokens.contains(token.name) {
            let lightValue = theme.lightValues[token.name]
            let darkValue = theme.darkValues[token.name]
            for value in [lightValue, darkValue].compactMap({ $0 }) {
                if case let .file(asset) = value, !asset.reference.isEmpty {
                    files.append(token.name)
                }
            }
            if let lightValue, let text = text(for: lightValue, of: token) {
                light.append("  \(token.name): \(text);")
            }
            if let darkValue, darkValue != lightValue, let text = text(for: darkValue, of: token) {
                dark.append("    \(token.name): \(text);")
            }
        }
        if !files.isEmpty { return .failure(.usesFiles(Array(Set(files)).sorted())) }
        if light.isEmpty && dark.isEmpty { return .failure(.noTokens) }

        var lines: [String] = []
        if !light.isEmpty {
            lines.append(":root {")
            lines.append(contentsOf: light)
            lines.append("}")
        }
        if !dark.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("@media (prefers-color-scheme: dark) {")
            lines.append("  :root {")
            lines.append(contentsOf: dark)
            lines.append("  }")
            lines.append("}")
        }
        return .success(lines.joined(separator: "\n") + "\n")
    }

    /// The value as CSS, or `nil` when it has no place in plain CSS (an
    /// empty file reference).
    private static func text(for value: ThemeValue, of token: ThemeTokenDescriptor) -> String? {
        switch value {
        case let .text(raw): "\"\(cleanText(raw))\""
        case let .file(asset): asset.reference.isEmpty ? nil : token.cssText(for: value)
        default: token.cssText(for: value)
        }
    }

    /// Text inside quotes without the characters that could end the string
    /// or start an escape: no quotes, no backslashes, no line breaks.
    public static func cleanText(_ raw: String) -> String {
        let kept = raw.unicodeScalars.filter { scalar in
            scalar != "\"" && scalar != "\\" && !CharacterSet.controlCharacters.contains(scalar)
        }
        return String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
    }
}

/// The token catalogue as JSON, for the Marketplace server: it checks
/// uploads against exactly the tokens and ranges this build knows.
public enum ThemeTokenManifest {
    public static func json(catalog: ThemeTokenCatalog = .standard,
                            limits: ThemeLimits = .standard) throws -> Data {
        var tokens: [[String: Any]] = []
        for token in catalog.tokens {
            var entry: [String: Any] = ["name": token.name, "kind": token.kind.label]
            switch token.kind {
            case let .number(spec):
                entry["kind"] = "number"
                entry["unit"] = spec.unit.rawValue
                entry["min"] = spec.minimum
                entry["max"] = spec.maximum
            case let .option(options):
                entry["options"] = options
            default:
                break
            }
            if !token.aliases.isEmpty { entry["aliases"] = token.aliases }
            tokens.append(entry)
        }
        let manifest: [String: Any] = [
            "format": ThemeFormat.current,
            "maxTextLength": limits.maxTextLength,
            "maxGradientStops": ThemeGradient.maximumStops,
            "dropped": ThemeCanonical.droppedTokens.sorted(),
            "tokens": tokens,
        ]
        return try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    }
}
