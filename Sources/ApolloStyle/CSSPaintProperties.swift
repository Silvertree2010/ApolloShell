enum CSSPaintProperties {
    static let entries: [CSSPropertyEntry] = [
        CSSPropertyEntry("color", inherits: true) { components, _ in .color(try CSSColorParser.color(components)) },
        CSSPropertyEntry("accent-color", inherits: true,
                         initial: .color(.system(name: "-apple-system-control-accent", alpha: 1))) { components, _ in
            .color(try CSSColorParser.color(components))
        },
        CSSPropertyEntry("background") { components, context in
            .layers(try CSSBackgroundParser.layers(components, context: context))
        },
        CSSPropertyEntry("background-color") { components, _ in .color(try CSSColorParser.color(components)) },
        CSSPropertyEntry("opacity") { components, _ in .number(try CSSRead.ratio(CSSRead.single(components))) },
        CSSPropertyEntry("border") { components, _ in try border(components) },
        CSSPropertyEntry("border-width") { components, _ in
            .length(try CSSRead.length(CSSRead.single(components), negative: false))
        },
        CSSPropertyEntry("border-color") { components, _ in .color(try CSSColorParser.color(components)) },
        CSSPropertyEntry("border-radius") { components, _ in .lengths(try CSSRead.fourSides(components, negative: false)) },
        CSSPropertyEntry("-apollo-corner-shape", initial: .keyword("continuous"),
                         parse: CSSKeywordParser.keyword(["continuous", "circular"])),
        CSSPropertyEntry("box-shadow") { components, _ in .shadows(try CSSEffects.shadows(components)) },
        CSSPropertyEntry("filter") { components, _ in .filters(try CSSEffects.filters(components)) },
        CSSPropertyEntry("-apollo-fade-edges") { components, _ in
            .length(try CSSRead.length(CSSRead.single(components), percent: true, negative: false))
        },
        CSSPropertyEntry("-apollo-join-radius") { components, _ in
            .length(try CSSRead.length(CSSRead.single(components), negative: false))
        },
        CSSPropertyEntry("-apollo-badge-color") { components, _ in .color(try CSSColorParser.color(components)) },
        CSSPropertyEntry("-apollo-badge-offset") { components, _ in
            let words = CSSList.words(components)
            guard words.count == 2 else { throw CSSValueError("'-apollo-badge-offset' needs x and y") }
            return .lengths(try words.map { try CSSRead.length($0) })
        },
    ]
}

private func border(_ components: [CSSComponent]) throws -> CSSValue {
    let words = CSSList.words(components)
    if words.count == 1, words[0].lowercasedIdent == "none" {
        return .border(width: 0, dashed: false, color: .currentColor)
    }
    var width: Double?
    var dashed: Bool?
    var color: CSSColor?
    for word in words {
        if let style = word.lowercasedIdent, style == "solid" || style == "dashed" {
            guard dashed == nil else { throw CSSValueError("border has one style, solid or dashed") }
            dashed = style == "dashed"
            continue
        }
        if let value = try CSSNumbers.numeric(word) {
            guard width == nil else { throw CSSValueError("border has one width") }
            guard value.dimension == .length || (value.dimension == .number && value.value == 0), value.value >= 0 else {
                throw CSSValueError("a border width is a length such as 1px, found '\(word.text)'")
            }
            width = value.value
            continue
        }
        guard color == nil else { throw CSSValueError("border is <width> solid|dashed <color>") }
        color = try CSSColorParser.color(word)
    }
    guard let width else { throw CSSValueError("border needs a width such as 1px") }
    return .border(width: width, dashed: dashed ?? false, color: color ?? .currentColor)
}
