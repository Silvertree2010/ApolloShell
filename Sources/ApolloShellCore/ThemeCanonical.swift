import Foundation

public enum ThemeCanonicalProblem: Error, Equatable, Sendable {
    case usesFiles([String])
    case noTokens
}

public enum ThemeCanonical {
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

    private static func text(for value: ThemeValue, of token: ThemeTokenDescriptor) -> String? {
        switch value {
        case let .text(raw): "\"\(cleanText(raw))\""
        case let .file(asset): asset.reference.isEmpty ? nil : token.cssText(for: value)
        default: token.cssText(for: value)
        }
    }

    public static func cleanText(_ raw: String) -> String {
        let kept = raw.unicodeScalars.filter { scalar in
            scalar != "\"" && scalar != "\\" && !CharacterSet.controlCharacters.contains(scalar)
        }
        return String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
    }
}

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
