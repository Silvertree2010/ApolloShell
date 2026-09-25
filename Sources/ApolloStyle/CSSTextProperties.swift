import Foundation

enum CSSTextProperties {
    static let genericFamilies: Set<String> = ["system-ui", "ui-monospace", "ui-rounded"]

    static let entries: [CSSPropertyEntry] = [
        CSSPropertyEntry("font-family", inherits: true) { components, _ in .fontFamilies(try fontFamilies(components)) },
        CSSPropertyEntry("font-size", inherits: true) { components, _ in
            let size = try CSSRead.length(CSSRead.single(components), negative: false)
            guard size.value > 0 else { throw CSSValueError("font-size must be larger than 0") }
            return .length(size)
        },
        CSSPropertyEntry("font-weight", inherits: true) { components, _ in try fontWeight(components) },
        CSSPropertyEntry("font-style", inherits: true, parse: CSSKeywordParser.keyword(["normal", "italic"])),
        CSSPropertyEntry("font-variant-numeric", inherits: true, parse: CSSKeywordParser.keyword(["normal", "tabular-nums"])),
        CSSPropertyEntry("line-height", inherits: true) { components, _ in try lineHeight(components) },
        CSSPropertyEntry("letter-spacing", inherits: true) { components, _ in
            let item = try CSSRead.single(components)
            if item.lowercasedIdent == "normal" { return .length(CSSLength(0, .points)) }
            return .length(try CSSRead.length(item))
        },
        CSSPropertyEntry("text-align", inherits: true,
                         parse: CSSKeywordParser.keyword(["start", "center", "end"], aliases: ["left": "start", "right": "end"])),
        CSSPropertyEntry("-apollo-font-scale", inherits: true, initial: .keyword("auto"),
                         parse: CSSKeywordParser.keyword(["auto", "none"])),
        CSSPropertyEntry("-apollo-image-rendering", initial: .keyword("original"),
                         parse: CSSKeywordParser.keyword(["original", "template"])),
        CSSPropertyEntry("-apollo-symbol-rendering", inherits: true,
                         parse: CSSKeywordParser.keyword(["monochrome", "hierarchical", "palette", "multicolor"])),
        CSSPropertyEntry("-apollo-symbol-effect", parse: CSSKeywordParser.keyword(["none", "variable-color", "pulse", "bounce"])),
        CSSPropertyEntry("-apollo-content-transition", parse: CSSKeywordParser.keyword(["none", "opacity", "numeric", "symbol"])),
        CSSPropertyEntry("-apollo-track-color") { components, _ in .color(try CSSColorParser.color(components)) },
        CSSPropertyEntry("-apollo-fill-color") { components, _ in .layers(try CSSBackgroundParser.paint(components)) },
        CSSPropertyEntry("-apollo-thumb-color") { components, _ in .color(try CSSColorParser.color(components)) },
        CSSPropertyEntry("-apollo-thumb-size") { components, _ in try thumbSize(components) },
        CSSPropertyEntry("-apollo-thumb-shadow") { components, _ in .shadows(try CSSEffects.shadows(components)) },
        CSSPropertyEntry("-apollo-fill-mode", initial: .keyword("center"),
                         parse: CSSKeywordParser.keyword(["center", "inside", "inside-linear"])),
        CSSPropertyEntry("-apollo-sweep-angle", initial: .angle(360)) { components, _ in
            .angle(try CSSRead.angle(CSSRead.single(components)))
        },
        CSSPropertyEntry("-apollo-stroke-width") { components, _ in
            .length(try CSSRead.length(CSSRead.single(components), negative: false))
        },
        CSSPropertyEntry("-apollo-start-angle", initial: .angle(-90)) { components, _ in
            .angle(try CSSRead.angle(CSSRead.single(components)))
        },
        CSSPropertyEntry("-apollo-fill") { components, _ in .layers(try CSSBackgroundParser.paint(components)) },
    ]
}

private func fontFamilies(_ components: [CSSComponent]) throws -> [String] {
    try CSSList.commaSeparated(components).map { words in
        if words.count == 1, case let .string(name)? = words[0].tokenKind {
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw CSSValueError("a font family name must not be empty")
            }
            return name
        }
        let names = words.compactMap(\.ident)
        guard !names.isEmpty, names.count == words.count else {
            throw CSSValueError("font-family takes names or quoted strings separated by commas")
        }
        let joined = names.joined(separator: " ")
        return CSSTextProperties.genericFamilies.contains(joined.lowercased()) ? joined.lowercased() : joined
    }
}

private func fontWeight(_ components: [CSSComponent]) throws -> CSSValue {
    let item = try CSSRead.single(components)
    switch item.lowercasedIdent {
    case "normal"?: return .number(400)
    case "bold"?: return .number(700)
    default: return .number(try CSSRead.number(item, minimum: 100, maximum: 900))
    }
}

private func lineHeight(_ components: [CSSComponent]) throws -> CSSValue {
    let item = try CSSRead.single(components)
    if item.lowercasedIdent == "normal" { return .keyword("normal") }
    let value = try CSSRead.numeric(item)
    if value.dimension == .number {
        guard value.value >= 0 else { throw CSSValueError("line-height must not be negative") }
        return .number(value.value)
    }
    return .length(try CSSRead.length(item, negative: false))
}

private func thumbSize(_ components: [CSSComponent]) throws -> CSSValue {
    let words = CSSList.words(components)
    guard (1...2).contains(words.count) else { throw CSSValueError("-apollo-thumb-size is <size> or <width> <height>") }
    let sizes = try words.map { try CSSRead.length($0, negative: false) }
    return .lengths(sizes.count == 1 ? [sizes[0], sizes[0]] : sizes)
}
