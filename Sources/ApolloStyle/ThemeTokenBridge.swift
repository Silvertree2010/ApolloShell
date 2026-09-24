import ApolloBase
import ApolloShellCore

public enum ThemeTokenBridge {
    public static func environment(for theme: Theme, appearance: Appearance) -> TokenEnvironment {
        let dark = effectiveAppearance(theme: theme, system: appearance) == .dark
        var values: [String: String] = [:]
        var set: Set<String> = []
        for token in ThemeTokenCatalog.standard.tokens {
            if token.name == ThemeColorToken.onAccent.name {
                if let readable = theme.readableColor(.onAccent, dark: dark) {
                    values[token.name] = readable.cssText
                }
                if theme.value(token.name, dark: dark) != nil { set.insert(token.name) }
                continue
            }
            guard let value = theme.value(token.name, dark: dark) else { continue }
            switch value {
            case let .gradient(gradient):
                guard !gradient.isEmpty else { continue }
                values[token.name] = gradient.cssText
            case let .file(asset):
                if asset.url != nil { set.insert(token.name) }
                continue
            case let .text(text):
                guard !text.isEmpty else { continue }
                values[token.name] = quoted(text)
            default:
                values[token.name] = token.cssText(for: value)
            }
            set.insert(token.name)
        }
        values.merge(DerivedTokens.values(for: theme, dark: dark)) { current, _ in current }
        values.merge(dark ? theme.foreignDarkValues : theme.foreignLightValues) { current, _ in current }
        return TokenEnvironment(values: values, declaredConfigTokens: [], setTokens: set)
    }

    public static func effectiveAppearance(theme: Theme, system: Appearance) -> Appearance {
        switch ThemeAppearance(theme: theme) {
        case .light: .light
        case .dark: .dark
        case .auto: system
        }
    }

    public static func undeclaredForeignTokens(in theme: Theme, declared: Set<String>) -> [Diagnostic] {
        let known = Set(declared.map { $0.lowercased() })
        let names = Set(theme.foreignLightValues.keys).union(theme.foreignDarkValues.keys)
        return names.filter { !known.contains($0) }.sorted().map {
            Diagnostic(.note, "the theme sets \($0), but the active config does not declare it in :root; it has no effect")
        }
    }

    static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }
}
