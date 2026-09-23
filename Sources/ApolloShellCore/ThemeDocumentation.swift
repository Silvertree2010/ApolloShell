import Foundation

/// Writes out the token directory - as a table for docs/THEMES.md and
/// as a complete example theme.
///
/// Why in the core and not by hand: docs that someone types out by hand stop
/// matching after the third new token. This way both come from the same
/// source, and a test compares the result with the files in the repo
/// - whoever adds a token without updating the docs sees a red
/// test instead of a silent gap.
public enum ThemeDocumentation {
    /// The tables for docs/THEMES.md, one per group.
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
                lines.append("| `\(token.name)` | \(typeText(token.kind)) | `\(token.defaultText())` | \(dark) | \(summary(token)) |")
            }
            blocks.append(lines.joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n\n")
    }

    /// The description, plus which token stands in when the theme leaves
    /// this one out - generated, so the docs cannot forget a fallback.
    public static func summary(_ token: ThemeTokenDescriptor) -> String {
        guard let fallback = token.fallback else { return token.summary }
        return "\(token.summary); unset, follows `\(fallback)`"
    }

    /// The first ```css block after the line `heading` in a Markdown text,
    /// without the fences - `nil` if there is none. Lets the example themes
    /// in docs/THEMES.md be loaded by tests and drawn by `--render-bars`
    /// straight from the docs, so the text a reader copies is the one that
    /// was checked.
    public static func cssBlock(after heading: String, in markdown: String) -> String? {
        guard let start = markdown.range(of: "\n" + heading + "\n"),
              let open = markdown.range(of: "```css\n", range: start.upperBound..<markdown.endIndex),
              let close = markdown.range(of: "\n```", range: open.upperBound..<markdown.endIndex)
        else { return nil }
        // Only this heading's block: another heading before the fence means
        // the section has none.
        if markdown.range(of: "\n#", range: start.upperBound..<open.lowerBound) != nil { return nil }
        return String(markdown[open.upperBound..<close.lowerBound]) + "\n"
    }

    /// What a type is called in the docs - including the bounds it is clamped
    /// to, and the allowed words of an enumeration.
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

    /// The table of symbols for docs/THEMES.md.
    public static func iconTable(catalog: ThemeIconCatalog = .standard) -> String {
        var lines = ["| File in `icons/` | Replaces | What it is |", "| --- | --- | --- |"]
        for icon in catalog.icons {
            let fallback = icon.fallback.isEmpty ? "the drawn emblem" : "`\(icon.fallback)`"
            lines.append("| `\(icon.id)` | \(fallback) | \(icon.summary) |")
        }
        return lines.joined(separator: "\n")
    }

    /// A theme that names every token - with the defaults, i.e. exactly the
    /// built-in look. Basis for examples/themes/full/theme.css.
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
