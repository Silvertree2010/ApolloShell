import ApolloShellCore

public enum Appearance: String, Sendable, Hashable {
    case light
    case dark
}

public struct TokenEnvironment: Sendable, Hashable {
    private let storage: [String: String]
    private let declared: Set<String>
    private let setNames: Set<String>

    public init(values: [String: String], declaredConfigTokens: Set<String> = []) {
        let lowered = TokenEnvironment.lowercasedKeys(values)
        let set = Set(lowered.keys.filter {
            $0.hasPrefix(ThemeTokenCatalog.prefix) && !DerivedTokens.names.contains($0)
        })
        self.init(storage: lowered, declared: Set(declaredConfigTokens.map { $0.lowercased() }), set: set)
    }

    init(values: [String: String], declaredConfigTokens: Set<String>, setTokens: Set<String>) {
        self.init(storage: TokenEnvironment.lowercasedKeys(values),
                  declared: Set(declaredConfigTokens.map { $0.lowercased() }),
                  set: Set(setTokens.map { $0.lowercased() }))
    }

    private init(storage: [String: String], declared: Set<String>, set: Set<String>) {
        self.storage = storage
        self.declared = declared
        setNames = set
    }

    public static let empty = TokenEnvironment(values: [:])

    public func value(_ customProperty: String) -> String? {
        let key = customProperty.lowercased()
        if key.hasPrefix(ThemeTokenCatalog.prefix) { return storage[key] }
        return declared.contains(key) ? storage[key] : nil
    }

    public var setTokens: Set<String> { setNames }

    public func declaring(_ names: Set<String>) -> TokenEnvironment {
        TokenEnvironment(storage: storage, declared: declared.union(names.map { $0.lowercased() }), set: setNames)
    }

    public var fontScale: Double {
        guard let raw = storage["--apollo-font-size"],
              let size = ThemeValueReader.number(raw, unit: .points), size > 0 else { return 1 }
        return size / 13
    }

    public var animationsEnabled: Bool { flag("--apollo-animations") ?? true }

    public var animationSpeed: Double {
        guard let raw = storage["--apollo-animation-speed"],
              let speed = ThemeValueReader.number(raw, unit: .scalar), speed >= 0 else { return 1 }
        return speed
    }

    public var glassEnabled: Bool { flag("--apollo-glass") ?? true }

    public var shadowsEnabled: Bool { flag("--apollo-shadows") ?? true }

    public var iconsMonochrome: Bool { storage["--apollo-icon-style"]?.lowercased() == "monochrome" }

    public var forcedAppearance: Appearance? {
        storage["--apollo-theme-appearance"].flatMap { Appearance(rawValue: $0.lowercased()) }
    }

    public func duration(_ seconds: Double) -> Double {
        guard animationsEnabled, animationSpeed > 0 else { return 0 }
        return seconds / animationSpeed
    }

    private func flag(_ name: String) -> Bool? {
        storage[name].flatMap(ThemeValueReader.flag)
    }

    private static func lowercasedKeys(_ values: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in values { result[key.lowercased()] = value }
        return result
    }
}

public struct StyleEnvironment: Sendable, Hashable {
    public var appearance: Appearance
    public var reduceMotion: Bool
    public var reduceTransparency: Bool
    public var tokens: TokenEnvironment

    public init(appearance: Appearance, reduceMotion: Bool, reduceTransparency: Bool, tokens: TokenEnvironment) {
        self.appearance = appearance
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.tokens = tokens
    }

    public var effectiveAppearance: Appearance { tokens.forcedAppearance ?? appearance }
}
