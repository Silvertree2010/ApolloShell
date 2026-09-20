import ApolloShellCore

// Short, typed handles for the tests. `.accent` exists as a color and as
// a gradient; here it is clear which one is meant. The app reads via
// `ShellStyle`.
extension Theme {
    func color(_ token: ThemeColorToken, dark: Bool = false) -> ThemeColor? { value(token, dark: dark) }
    func gradient(_ token: ThemeGradientToken, dark: Bool = false) -> ThemeGradient? { value(token, dark: dark) }
    func number(_ token: ThemeNumberToken, dark: Bool = false) -> Double? { value(token, dark: dark) }
    func text(_ token: ThemeTextToken, dark: Bool = false) -> String? { value(token, dark: dark) }
    func option(_ token: ThemeOptionToken, dark: Bool = false) -> String? { value(token, dark: dark) }
    func flag(_ token: ThemeFlagToken, dark: Bool = false) -> Bool? { value(token, dark: dark) }
}
