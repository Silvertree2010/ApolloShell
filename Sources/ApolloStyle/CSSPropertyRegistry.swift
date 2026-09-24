import ApolloShellCore
import Foundation

struct CSSParseContext: Sendable, Hashable {
    var assetRoot: URL?
    var limits: ThemeLimits

    init(assetRoot: URL? = nil, limits: ThemeLimits = .standard) {
        self.assetRoot = assetRoot
        self.limits = limits
    }
}

typealias CSSPropertyParser = @Sendable ([CSSComponent], CSSParseContext) throws -> CSSValue

struct CSSPropertyEntry: Sendable {
    let schema: CSSPropertySchema
    let parse: CSSPropertyParser

    init(_ name: String, inherits: Bool = false, initial: CSSValue? = nil, parse: @escaping CSSPropertyParser) {
        schema = CSSPropertySchema(name: name, inherits: inherits, initial: initial, feature: "core")
        self.parse = parse
    }
}

enum CSSKeywordParser {
    static func keyword(_ allowed: [String], aliases: [String: String] = [:]) -> CSSPropertyParser {
        { components, _ in .keyword(try CSSRead.keyword(CSSRead.single(components), allowed, aliases: aliases)) }
    }
}

public enum CSSPropertyRegistry {
    static let groups: [[CSSPropertyEntry]] = [
        CSSBoxProperties.entries,
    ]

    static let entries: [String: CSSPropertyEntry] = {
        var table: [String: CSSPropertyEntry] = [:]
        for group in groups {
            for entry in group { table[entry.schema.name] = entry }
        }
        return table
    }()

    public static let builtin: [String: CSSPropertySchema] = entries.mapValues(\.schema)

    static func parse(_ property: String, _ text: String, context: CSSParseContext) throws -> CSSValue {
        guard let entry = entries[property] else { throw CSSValueError("unknown property '\(property)'") }
        let components = CSSComponentParser.parse(text: text)
        guard !CSSList.words(components).isEmpty else { throw CSSValueError("'\(property)' has no value") }
        return try entry.parse(components, context)
    }
}
