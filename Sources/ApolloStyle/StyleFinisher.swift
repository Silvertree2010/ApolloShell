enum StyleFinisher {
    static let windowBackground = BackgroundLayer.color(.system(name: "-apple-system-window-background", alpha: 1))
    static let reducedMotionAnimations: Set<String> = ["spin", "wiggle", "bounce"]
    static let reducedMotionTransitions: Set<String> = ["match", "transform", "size"]

    static func finish(_ values: inout [String: CSSValue], winners: [String: CascadeRank], declared: Set<String>,
                       environment: StyleEnvironment) {
        composeBackground(&values, winners: winners)
        composeBorder(&values, winners: winners)
        composeSides("padding", &values, winners: winners)
        composeSides("margin", &values, winners: winners)
        composeFlex(&values, winners: winners)
        scaleFont(&values, declared: declared, tokens: environment.tokens)
        applyMotion(&values, environment: environment)
        applySurfaces(&values, environment: environment)
    }

    private static func composeBackground(_ values: inout [String: CSSValue], winners: [String: CascadeRank]) {
        var layers: [BackgroundLayer]?
        if case let .layers(found)? = values["background"] { layers = found }
        var color: CSSColor?
        if case let .color(found)? = values["background-color"] { color = found }
        values["background-color"] = nil
        guard layers != nil || color != nil else { return }
        var result = layers ?? []
        if let color {
            let colorWins: Bool
            switch (winners["background"], winners["background-color"]) {
            case (nil, _): colorWins = true
            case let (shorthand?, longhand?): colorWins = longhand > shorthand
            case (_?, nil): colorWins = false
            }
            if colorWins { result.append(.color(color)) }
        }
        values["background"] = .layers(result)
    }

    private static func composeBorder(_ values: inout [String: CSSValue], winners: [String: CascadeRank]) {
        var width: Double?
        var dashed = false
        var color = CSSColor.currentColor
        var widthRank: CascadeRank?
        var colorRank: CascadeRank?
        if case let .border(shorthandWidth, shorthandDashed, shorthandColor)? = values["border"] {
            width = shorthandWidth
            dashed = shorthandDashed
            color = shorthandColor
            widthRank = winners["border"]
            colorRank = winners["border"]
        }
        if case let .length(length)? = values["border-width"], outranks(winners["border-width"], widthRank) {
            width = length.value
        }
        if case let .color(found)? = values["border-color"], outranks(winners["border-color"], colorRank) {
            color = found
        }
        values["border-width"] = nil
        values["border-color"] = nil
        if let width, width > 0 {
            values["border"] = .border(width: width, dashed: dashed, color: color)
        } else {
            values["border"] = nil
        }
    }

    private static func composeSides(_ box: String, _ values: inout [String: CSSValue], winners: [String: CascadeRank]) {
        let names = CSSBoxProperties.sides.map { "\(box)-\($0)" }
        var sides = [CSSLength](repeating: CSSLength(0, .points), count: 4)
        var present = false
        if case let .lengths(found)? = values[box], found.count == 4 {
            sides = found
            present = true
        }
        for (index, name) in names.enumerated() {
            if case let .length(length)? = values[name], outranks(winners[name], winners[box]) {
                sides[index] = length
                present = true
            }
            values[name] = nil
        }
        if present { values[box] = .lengths(sides) }
    }

    private static func composeFlex(_ values: inout [String: CSSValue], winners: [String: CascadeRank]) {
        defer { values["flex"] = nil }
        guard let rank = winners["flex"] else { return }
        var parts: [CSSValue]?
        if case let .lengths(found)? = values["flex"], found.count == 3 {
            parts = [.number(found[0].value), .number(found[1].value), .length(found[2])]
        }
        for (index, name) in ["flex-grow", "flex-shrink", "flex-basis"].enumerated() where !outranks(winners[name], rank) {
            values[name] = parts?[index]
        }
    }

    private static func outranks(_ candidate: CascadeRank?, _ current: CascadeRank?) -> Bool {
        guard let current else { return true }
        guard let candidate else { return false }
        return candidate > current
    }

    private static func scaleFont(_ values: inout [String: CSSValue], declared: Set<String>, tokens: TokenEnvironment) {
        guard declared.contains("font-size"), case let .length(size)? = values["font-size"], size.unit == .points else { return }
        if case .keyword("none")? = values["-apollo-font-scale"] { return }
        values["font-size"] = .length(CSSLength(size.value * tokens.fontScale, .points))
    }

    private static func applyMotion(_ values: inout [String: CSSValue], environment: StyleEnvironment) {
        let tokens = environment.tokens
        let stopped = !tokens.animationsEnabled || tokens.animationSpeed == 0
        if case let .transitions(list)? = values["transition"] {
            var result = list.map { Transition(property: $0.property, duration: tokens.duration($0.duration), curve: $0.curve) }
            if environment.reduceMotion { result.removeAll { reducedMotionTransitions.contains($0.property) } }
            values["transition"] = .transitions(result)
        }
        for key in ["-apollo-appear", "-apollo-disappear", "-apollo-badge-appear"] {
            guard case let .appear(list)? = values[key] else { continue }
            values[key] = .appear(list.map {
                AppearTransition(effects: environment.reduceMotion ? [.fade] : $0.effects,
                                 duration: tokens.duration($0.duration), curve: $0.curve)
            })
        }
        if case let .animation(name, duration, count)? = values["animation"] {
            if stopped || (environment.reduceMotion && reducedMotionAnimations.contains(name)) {
                values["animation"] = .keyword("none")
            } else {
                values["animation"] = .animation(name: name, duration: tokens.duration(duration), repeatCount: count)
            }
        }
        if case let .duration(delay)? = values["animation-delay"] {
            values["animation-delay"] = .duration(stopped ? 0 : delay / tokens.animationSpeed)
        }
    }

    private static func applySurfaces(_ values: inout [String: CSSValue], environment: StyleEnvironment) {
        let tokens = environment.tokens
        if case let .layers(list)? = values["background"] {
            var result: [BackgroundLayer] = []
            for layer in list {
                switch layer {
                case .glass:
                    if environment.reduceTransparency {
                        result.append(windowBackground)
                    } else if tokens.glassEnabled {
                        result.append(layer)
                    }
                case .material:
                    result.append(environment.reduceTransparency ? windowBackground : layer)
                default:
                    result.append(layer)
                }
            }
            values["background"] = .layers(result)
        }
        if !tokens.shadowsEnabled {
            if values["box-shadow"] != nil { values["box-shadow"] = .shadows([]) }
            if values["-apollo-thumb-shadow"] != nil { values["-apollo-thumb-shadow"] = .shadows([]) }
        }
    }
}
