enum CSSEffects {
    static func shadows(_ components: [CSSComponent]) throws -> [Shadow] {
        let parts = CSSList.commaSeparated(components)
        if parts.count == 1, parts[0].count == 1, parts[0][0].lowercasedIdent == "none" { return [] }
        return try parts.map { try shadow($0, allowSpread: true) }
    }

    static func shadow(_ words: [CSSComponent], allowSpread: Bool) throws -> Shadow {
        var lengths: [Double] = []
        var color: CSSColor?
        for word in words {
            if word.lowercasedIdent == "inset" { throw CSSValueError("inset shadows are not supported") }
            if let value = try CSSNumbers.numeric(word) {
                guard value.dimension == .length || (value.dimension == .number && value.value == 0) else {
                    throw CSSValueError("shadow offsets and blur are lengths, found '\(word.text)'")
                }
                lengths.append(value.value)
                continue
            }
            guard color == nil else { throw CSSValueError("a shadow has one color") }
            color = try CSSColorParser.color(word)
        }
        let maximum = allowSpread ? 4 : 3
        guard (2...maximum).contains(lengths.count) else {
            throw CSSValueError(allowSpread ? "a shadow is x y [blur [spread]] color" : "drop-shadow() is x y [blur] color")
        }
        guard lengths.count < 3 || lengths[2] >= 0 else { throw CSSValueError("shadow blur must not be negative") }
        return Shadow(x: lengths[0], y: lengths[1],
                      blur: lengths.count > 2 ? lengths[2] : 0,
                      spread: lengths.count > 3 ? lengths[3] : 0,
                      color: color ?? .currentColor)
    }

    static func filters(_ components: [CSSComponent]) throws -> [FilterOperation] {
        let words = CSSList.words(components)
        if words.count == 1, words[0].lowercasedIdent == "none" { return [] }
        return try words.map { word in
            guard case let .function(name, arguments, _) = word else {
                throw CSSValueError("filter takes drop-shadow() and blur(), found '\(word.text)'")
            }
            switch name.lowercased() {
            case "drop-shadow":
                return .dropShadow(try shadow(CSSList.words(arguments), allowSpread: false))
            case "blur":
                return .blur(try CSSRead.length(CSSRead.single(arguments), negative: false).value)
            default:
                throw CSSValueError("filter \(name)() is not supported")
            }
        }
    }
}
