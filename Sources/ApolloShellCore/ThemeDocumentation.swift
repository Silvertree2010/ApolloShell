import Foundation

public enum ThemeDocumentation {
    public static func markdownTables(catalog: ThemeTokenCatalog = .standard) -> String {
        var blocks: [String] = []
        for group in ThemeTokenGroup.allCases {
            let tokens = catalog.tokens.filter { $0.group == group }
            guard !tokens.isEmpty else { continue }
            var lines = ["### \(group.rawValue)", "",
                         "| Token | Type | Default | Dark | What it does |",
                         "| --- | --- | --- | --- | --- |"]
            for token in tokens {
                let dark = token.darkDefaultValue == token.defaultValue ? "" : "`\(token.defaultText(dark: true))`"
                lines.append("| `\(token.name)` | \(typeText(token.kind)) | `\(token.defaultText())` | \(dark) | \(token.summary) |")
            }
            blocks.append(lines.joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n\n")
    }

    public static func typeText(_ kind: ThemeTokenKind) -> String {
        switch kind {
        case let .number(spec):
            "\(kind.label) (\(spec.unit.cssText(spec.minimum))–\(spec.unit.cssText(spec.maximum)))"
        case let .option(values):
            "\(kind.label) (\(values.joined(separator: ", ")))"
        default:
            kind.label
        }
    }

    public static func iconTable(catalog: ThemeIconCatalog = .standard) -> String {
        var lines = ["| File in `icons/` | Replaces | What it is |", "| --- | --- | --- |"]
        for icon in catalog.icons {
            let fallback = icon.fallback.isEmpty ? "the drawn emblem" : "`\(icon.fallback)`"
            lines.append("| `\(icon.id)` | \(fallback) | \(icon.summary) |")
        }
        return lines.joined(separator: "\n")
    }

    public static func exampleCSS(catalog: ThemeTokenCatalog = .standard) -> String {
        var lines: [String] = [":root {"]
        var group: ThemeTokenGroup?
        for token in catalog.tokens {
            if token.group != group {
                if group != nil { lines.append("") }
                lines.append("  /* \(token.group.rawValue) */")
                group = token.group
            }
            lines.append("  \(token.name): \(token.defaultText());")
        }
        lines.append("}")
        let dark = catalog.tokens.filter { $0.darkDefaultValue != $0.defaultValue }
        guard !dark.isEmpty else { return lines.joined(separator: "\n") + "\n" }
        lines.append("")
        lines.append("@media (prefers-color-scheme: dark) {")
        lines.append("  :root {")
        for token in dark {
            lines.append("    \(token.name): \(token.defaultText(dark: true));")
        }
        lines.append("  }")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }
}
