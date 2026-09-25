import ApolloConfig
import ApolloShellCore
import ApolloStyle

enum ThemeRoot {
    static func value(theme: Theme?, tokens: TokenEnvironment, dark: Bool) -> Value {
        let set = tokens.setTokens.sorted().compactMap { name -> (String, Value)? in
            name.hasPrefix("--apollo-") ? (String(name.dropFirst("--apollo-".count)), .bool(true)) : nil
        }
        return .record(Record([
            ("id", theme.map { .string($0.identifier) } ?? .null),
            ("name", theme.map { .string($0.title) } ?? .null),
            ("appearance", .string(dark ? "dark" : "light")),
            ("dark", .bool(dark)),
            ("set", .record(Record(set))),
        ]))
    }
}
