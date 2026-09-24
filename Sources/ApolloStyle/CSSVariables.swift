import ApolloShellCore

enum CSSVariables {
    static let maximumDepth = 32

    static func containsVar(_ text: String) -> Bool {
        text.range(of: "var(", options: .caseInsensitive) != nil
    }

    static func substitute(_ text: String, lookup: (String) -> String?) throws -> String {
        try substitute(CSSComponentParser.parse(text: text), lookup: lookup, depth: 0)
    }

    private static func substitute(_ components: [CSSComponent], lookup: (String) -> String?, depth: Int) throws -> String {
        guard depth <= maximumDepth else {
            throw CSSValueError("var() is nested more than \(maximumDepth) levels deep")
        }
        var result = ""
        for component in components {
            switch component {
            case let .function(name, arguments, _) where name.lowercased() == "var":
                result += try resolve(arguments, lookup: lookup, depth: depth)
            case let .function(_, arguments, opening):
                result += opening.text + (try substitute(arguments, lookup: lookup, depth: depth)) + ")"
            case let .block(kind, contents, opening):
                result += opening.text + (try substitute(contents, lookup: lookup, depth: depth)) + kind.close
            case let .token(token):
                result += token.text
            }
        }
        return result
    }

    private static func resolve(_ arguments: [CSSComponent], lookup: (String) -> String?, depth: Int) throws -> String {
        let comma = arguments.firstIndex(where: \.isComma)
        let nameWords = CSSList.words(Array(arguments[..<(comma ?? arguments.endIndex)]))
        guard nameWords.count == 1, let name = nameWords[0].ident, name.hasPrefix("--") else {
            throw CSSValueError("var() needs a custom property name such as var(--name)")
        }
        if let value = lookup(name) {
            return try substitute(CSSComponentParser.parse(text: value), lookup: lookup, depth: depth + 1)
        }
        guard let comma else { throw CSSValueError("\(name) is not set and var() has no fallback") }
        return try substitute(Array(arguments[(comma + 1)...]), lookup: lookup, depth: depth + 1)
    }
}

final class CustomPropertyResolver {
    private let own: [String: String]
    private let inherited: [String: String]
    private let tokens: TokenEnvironment
    private var resolved: [String: String] = [:]
    private var failed: Set<String> = []
    private var visiting: Set<String> = []
    private(set) var failures: [(name: String, message: String)] = []

    init(own: [String: String], inherited: [String: String], tokens: TokenEnvironment) {
        self.own = own
        self.inherited = inherited
        self.tokens = tokens
    }

    func resolveAll() -> [String: String] {
        var result = inherited
        for name in own.keys.sorted() {
            if let value = value(name) {
                result[name] = value
            } else {
                result.removeValue(forKey: name)
            }
        }
        return result
    }

    func value(_ name: String) -> String? {
        if name.lowercased().hasPrefix(ThemeTokenCatalog.prefix) { return tokens.value(name) }
        if let done = resolved[name] { return done }
        if failed.contains(name) { return nil }
        guard let raw = own[name] else { return inherited[name] }
        guard visiting.insert(name).inserted else { return nil }
        defer { visiting.remove(name) }
        do {
            let text = try CSSVariables.substitute(raw) { self.value($0) }
            resolved[name] = text
            return text
        } catch {
            failed.insert(name)
            failures.append((name: name, message: (error as? CSSValueError)?.message ?? "invalid value"))
            return nil
        }
    }
}
