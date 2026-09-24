enum CSSBoxProperties {
    static let flexAliases = ["flex-start": "start", "flex-end": "end"]

    static let entries: [CSSPropertyEntry] = [
        CSSPropertyEntry("width") { components, _ in try size(components) },
        CSSPropertyEntry("height") { components, _ in try size(components) },
        CSSPropertyEntry("min-width") { components, _ in try size(components) },
        CSSPropertyEntry("min-height") { components, _ in try size(components) },
        CSSPropertyEntry("max-width") { components, _ in try maximumSize(components) },
        CSSPropertyEntry("max-height") { components, _ in try maximumSize(components) },
        CSSPropertyEntry("aspect-ratio") { components, _ in try aspectRatio(components) },
        CSSPropertyEntry("padding") { components, _ in .lengths(try CSSRead.fourSides(components, negative: false)) },
        CSSPropertyEntry("margin") { components, _ in .lengths(try CSSRead.fourSides(components, negative: true)) },
        CSSPropertyEntry("gap") { components, _ in try gap(components) },
        CSSPropertyEntry("row-gap") { components, _ in try gap(components) },
        CSSPropertyEntry("column-gap") { components, _ in try gap(components) },
        CSSPropertyEntry("flex-grow") { components, _ in .number(try CSSRead.number(CSSRead.single(components), minimum: 0)) },
        CSSPropertyEntry("flex-shrink") { components, _ in .number(try CSSRead.number(CSSRead.single(components), minimum: 0)) },
        CSSPropertyEntry("align-items", parse: CSSKeywordParser.keyword(["start", "center", "end", "stretch"], aliases: flexAliases)),
        CSSPropertyEntry("align-self", parse: CSSKeywordParser.keyword(["auto", "start", "center", "end", "stretch"], aliases: flexAliases)),
        CSSPropertyEntry("justify-self", parse: CSSKeywordParser.keyword(["auto", "start", "center", "end"], aliases: flexAliases)),
        CSSPropertyEntry("justify-content", parse: CSSKeywordParser.keyword(
            ["start", "center", "end", "space-between", "space-around", "space-evenly"], aliases: flexAliases)),
        CSSPropertyEntry("grid-template-columns") { components, _ in try gridColumns(components) },
        CSSPropertyEntry("grid-auto-rows") { components, _ in
            .length(try CSSRead.length(CSSRead.single(components), auto: true, negative: false))
        },
        CSSPropertyEntry("grid-column") { components, _ in try span(components) },
        CSSPropertyEntry("grid-row") { components, _ in try span(components) },
        CSSPropertyEntry("overflow", parse: CSSKeywordParser.keyword(["visible", "hidden"])),
        CSSPropertyEntry("z-index") { components, _ in
            .number(Double(try CSSRead.integer(CSSRead.single(components), in: -10_000...10_000)))
        },
        CSSPropertyEntry("pointer-events", inherits: true, parse: CSSKeywordParser.keyword(["auto", "none"])),
        CSSPropertyEntry("cursor", inherits: true, parse: CSSKeywordParser.keyword(["default", "pointer", "text", "grab"])),
    ]
}

extension CSSRead {
    static func fourSides(_ components: [CSSComponent], negative: Bool) throws -> [CSSLength] {
        let words = CSSList.words(components)
        guard (1...4).contains(words.count) else { throw CSSValueError("expected 1 to 4 lengths") }
        let values = try words.map { try CSSRead.length($0, percent: true, negative: negative) }
        switch values.count {
        case 1: return [values[0], values[0], values[0], values[0]]
        case 2: return [values[0], values[1], values[0], values[1]]
        case 3: return [values[0], values[1], values[2], values[1]]
        default: return values
        }
    }
}

private func size(_ components: [CSSComponent]) throws -> CSSValue {
    .length(try CSSRead.length(CSSRead.single(components), percent: true, auto: true, negative: false))
}

private func maximumSize(_ components: [CSSComponent]) throws -> CSSValue {
    let item = try CSSRead.single(components)
    if item.lowercasedIdent == "none" { return .length(CSSLength(0, .auto)) }
    return .length(try CSSRead.length(item, percent: true, auto: true, negative: false))
}

private func gap(_ components: [CSSComponent]) throws -> CSSValue {
    .length(try CSSRead.length(CSSRead.single(components), negative: false))
}

private func aspectRatio(_ components: [CSSComponent]) throws -> CSSValue {
    let words = CSSList.words(components)
    if words.count == 1, words[0].lowercasedIdent == "auto" { return .keyword("auto") }
    if words.count == 1 {
        let ratio = try CSSRead.number(words[0])
        guard ratio > 0 else { throw CSSValueError("aspect-ratio needs a positive number") }
        return .number(ratio)
    }
    guard words.count == 3, words[1].delimCharacter == "/" else { throw CSSValueError("aspect-ratio is a number or a / b") }
    let width = try CSSRead.number(words[0])
    let height = try CSSRead.number(words[2])
    guard width > 0, height > 0 else { throw CSSValueError("aspect-ratio needs positive numbers") }
    return .number(width / height)
}

private func gridColumns(_ components: [CSSComponent]) throws -> CSSValue {
    let words = CSSList.words(components)
    if words.count == 1, case let .function(name, arguments, _) = words[0], name.lowercased() == "repeat" {
        let parts = CSSList.commaSeparated(arguments)
        guard parts.count == 2, parts[0].count == 1, parts[1].count == 1 else {
            throw CSSValueError("repeat() is repeat(N, <track>)")
        }
        let count = try CSSRead.integer(parts[0][0], in: 1...64)
        let track = try gridTrack(parts[1][0])
        return .gridColumns(Array(repeating: track, count: count))
    }
    guard (1...64).contains(words.count) else { throw CSSValueError("grid-template-columns takes 1 to 64 tracks") }
    return .gridColumns(try words.map(gridTrack))
}

private func gridTrack(_ component: CSSComponent) throws -> CSSLength {
    if let value = try CSSNumbers.numeric(component), value.dimension == .fraction {
        guard value.value > 0 else { throw CSSValueError("'\(component.text)' must be positive") }
        return CSSLength(value.value, .fraction)
    }
    return try CSSRead.length(component, percent: true, auto: true, negative: false)
}

private func span(_ components: [CSSComponent]) throws -> CSSValue {
    let words = CSSList.words(components)
    guard words.count == 2, words[0].lowercasedIdent == "span" else { throw CSSValueError("expected span N") }
    return .span(try CSSRead.integer(words[1], in: 1...64))
}
