import ApolloShellCore

public enum DerivedTokens {
    struct Rule: Sendable {
        let name: String
        let gradient: ThemeGradientToken
        let color: ThemeColorToken
        let opacity: ThemeNumberToken?
    }

    static let rules: [Rule] = [
        Rule(name: "--apollo-bar-fill", gradient: .bar, color: .bar, opacity: .barOpacity),
        Rule(name: "--apollo-panel-fill", gradient: .panel, color: .panel, opacity: .panelOpacity),
        Rule(name: "--apollo-card-fill", gradient: .card, color: .card, opacity: nil),
        Rule(name: "--apollo-surface-fill", gradient: .surface, color: .surface, opacity: .surfaceOpacity),
        Rule(name: "--apollo-accent-fill", gradient: .accent, color: .accent, opacity: nil),
        Rule(name: "--apollo-toast-fill", gradient: .toast, color: .toast, opacity: nil),
        Rule(name: "--apollo-launcher-highlight-fill", gradient: .launcherHighlight, color: .launcherHighlight, opacity: nil),
        Rule(name: "--apollo-background-fill", gradient: .background, color: .background, opacity: nil),
    ]

    public static let names: [String] = rules.map(\.name)

    public static func values(for theme: Theme, dark: Bool) -> [String: String] {
        var result: [String: String] = [:]
        for rule in rules {
            let opacity = rule.opacity.flatMap { theme.value($0, dark: dark) } ?? 1
            if let gradient = theme.value(rule.gradient, dark: dark), !gradient.isEmpty {
                let stops = gradient.stops.map {
                    ThemeGradient.Stop(color: $0.color.withAlpha($0.color.alpha * opacity), position: $0.position)
                }
                result[rule.name] = ThemeGradient(angle: gradient.angle, stops: stops).cssText
            } else if let color = theme.value(rule.color, dark: dark) {
                result[rule.name] = color.withAlpha(color.alpha * opacity).cssText
            }
        }
        return result
    }
}
