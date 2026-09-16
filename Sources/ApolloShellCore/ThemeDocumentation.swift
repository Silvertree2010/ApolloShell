import Foundation

/// Schreibt das Token-Verzeichnis auf - als Tabelle fuer docs/THEMES.md und
/// als vollstaendiges Beispiel-Theme.
///
/// Warum im Kern und nicht von Hand: eine Doku, die jemand abtippt, stimmt
/// nach dem dritten neuen Token nicht mehr. So kommt beides aus derselben
/// Quelle, und ein Test vergleicht das Ergebnis mit den Dateien im Verzeichnis
/// - wer ein Token hinzufuegt, ohne die Doku nachzuziehen, sieht einen roten
/// Test statt einer stillen Luecke.
public enum ThemeDocumentation {
    /// Die Tabellen fuer docs/THEMES.md, eine je Gruppe.
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

    /// Wie ein Typ in der Doku heisst - samt der Grenzen, an denen geklemmt
    /// wird, und den erlaubten Woertern einer Aufzaehlung.
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

    /// Ein Theme, das jedes Token nennt - mit den Vorgaben, also genau dem
    /// eingebauten Aussehen. Grundlage fuer examples/themes/full/theme.css.
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
