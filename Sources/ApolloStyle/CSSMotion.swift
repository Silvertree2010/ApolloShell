import ApolloShellCore

enum CSSTimingCurves {
    static let standard = TimingCurve.cubicBezier(0.25, 0.1, 0.25, 1)

    static let named: [String: TimingCurve] = [
        "linear": .linear,
        "ease": standard,
        "ease-in": .cubicBezier(0.42, 0, 1, 1),
        "ease-out": .cubicBezier(0, 0, 0.58, 1),
        "ease-in-out": .cubicBezier(0.42, 0, 0.58, 1),
        "spatial": .cubicBezier(MotionCurve.spatial.x1, MotionCurve.spatial.y1, MotionCurve.spatial.x2, MotionCurve.spatial.y2),
        "effects": .cubicBezier(0.34, 0.8, 0.34, 1),
        "effects-slow": .cubicBezier(0.34, 0.88, 0.34, 1),
        "emphasized": .cubicBezier(0.2, 0, 0, 1),
    ]

    static func curve(_ component: CSSComponent) throws -> TimingCurve? {
        if let name = component.lowercasedIdent { return named[name] }
        guard case let .function(name, arguments, _) = component else { return nil }
        switch name.lowercased() {
        case "cubic-bezier":
            let values = try CSSList.commaSeparated(arguments).map { try CSSRead.number(CSSRead.single($0)) }
            guard values.count == 4, (0...1).contains(values[0]), (0...1).contains(values[2]) else {
                throw CSSValueError("cubic-bezier() takes four numbers, the first and third between 0 and 1")
            }
            return .cubicBezier(values[0], values[1], values[2], values[3])
        case "spring":
            let values = try CSSList.commaSeparated(arguments).map { try CSSRead.number(CSSRead.single($0)) }
            guard values.count == 2, values[0] > 0, values[1] >= 0 else {
                throw CSSValueError("spring() takes a response above 0 and a damping of 0 or more")
            }
            return .spring(response: values[0], damping: values[1])
        default:
            return nil
        }
    }
}

enum CSSMotionParser {
    static let transitionTargets: Set<String> = ["all", "size", "value", "content", "match"]
    static let motionProperties: Set<String> = ["transition", "-apollo-appear", "-apollo-disappear", "animation", "animation-delay"]
    static let animationNames: Set<String> = ["spin", "pulse", "wiggle", "bounce"]
    static let slideEdges: [String: String] = [
        "top": "top", "bottom": "bottom", "leading": "leading", "trailing": "trailing", "left": "leading", "right": "trailing",
    ]

    static func transitions(_ components: [CSSComponent]) throws -> [Transition] {
        let parts = CSSList.commaSeparated(components)
        if parts.count == 1, parts[0].count == 1, parts[0][0].lowercasedIdent == "none" { return [] }
        return try parts.map { words in
            var property: String?
            var duration: Double?
            var curve: TimingCurve?
            for word in words {
                if let value = try CSSNumbers.numeric(word) {
                    guard duration == nil, value.dimension == .duration || (value.dimension == .number && value.value == 0) else {
                        throw CSSValueError("a transition is <property> <duration> [<curve>]")
                    }
                    guard value.value >= 0 else { throw CSSValueError("a transition duration must not be negative") }
                    duration = value.value
                    continue
                }
                if let found = try CSSTimingCurves.curve(word) {
                    guard curve == nil else { throw CSSValueError("a transition has one curve") }
                    curve = found
                    continue
                }
                guard property == nil, let name = word.lowercasedIdent else {
                    throw CSSValueError("a transition is <property> <duration> [<curve>], found '\(word.text)'")
                }
                guard transitionTargets.contains(name) || animatable(name) else {
                    throw CSSValueError("'\(name)' cannot be animated with transition")
                }
                property = name
            }
            guard let property, let duration else { throw CSSValueError("a transition is <property> <duration> [<curve>]") }
            return Transition(property: property, duration: duration, curve: curve ?? CSSTimingCurves.standard)
        }
    }

    static func animatable(_ name: String) -> Bool {
        CSSPropertyRegistry.builtin[name] != nil && !motionProperties.contains(name)
    }

    static func appear(_ components: [CSSComponent]) throws -> [AppearTransition] {
        let parts = CSSList.commaSeparated(components)
        if parts.count == 1, parts[0].count == 1, parts[0][0].lowercasedIdent == "none" { return [] }
        return try parts.map { words in
            var effects: [AppearEffect] = []
            var duration: Double?
            var curve: TimingCurve?
            for word in words {
                if let effect = try effect(word) {
                    guard duration == nil else { throw CSSValueError("effects come before the duration") }
                    effects.append(effect)
                    continue
                }
                if let value = try CSSNumbers.numeric(word) {
                    guard duration == nil, value.dimension == .duration, value.value >= 0 else {
                        throw CSSValueError("-apollo-appear is <effect>+ <duration> [<curve>]")
                    }
                    duration = value.value
                    continue
                }
                if let found = try CSSTimingCurves.curve(word), curve == nil {
                    curve = found
                    continue
                }
                throw CSSValueError("unknown effect '\(word.text)'; effects are fade, scale(), slide(), blur()")
            }
            guard !effects.isEmpty, let duration else { throw CSSValueError("-apollo-appear is <effect>+ <duration> [<curve>]") }
            return AppearTransition(effects: effects, duration: duration, curve: curve ?? CSSTimingCurves.standard)
        }
    }

    static func effect(_ word: CSSComponent) throws -> AppearEffect? {
        if word.lowercasedIdent == "fade" { return .fade }
        guard case let .function(name, arguments, _) = word else { return nil }
        let words = CSSList.words(arguments)
        switch name.lowercased() {
        case "scale":
            return .scale(try CSSRead.number(CSSRead.single(arguments), minimum: 0))
        case "slide":
            guard (1...2).contains(words.count), let edgeName = words[0].lowercasedIdent, let edge = slideEdges[edgeName] else {
                throw CSSValueError("slide() takes top, bottom, leading or trailing and an optional length")
            }
            var distance: Double?
            if words.count == 2 { distance = try CSSRead.length(words[1]).value }
            return .slide(edge: edge, distance: distance)
        case "blur":
            return .blur(try CSSRead.length(CSSRead.single(arguments), negative: false).value)
        default:
            return nil
        }
    }

    static func transform(_ components: [CSSComponent]) throws -> [TransformOperation] {
        let words = CSSList.words(components)
        if words.count == 1, words[0].lowercasedIdent == "none" { return [] }
        return try words.map { word in
            guard case let .function(name, arguments, _) = word else {
                throw CSSValueError("transform takes rotate(), scale() and translate(), found '\(word.text)'")
            }
            let parts = CSSList.commaSeparated(arguments)
            switch name.lowercased() {
            case "rotate":
                guard parts.count == 1 else { throw CSSValueError("rotate() takes one angle") }
                return .rotate(try CSSRead.angle(CSSRead.single(parts[0])))
            case "scale":
                guard parts.count == 1 else { throw CSSValueError("scale() takes one number") }
                return .scale(try CSSRead.number(CSSRead.single(parts[0])))
            case "translate":
                guard (1...2).contains(parts.count) else { throw CSSValueError("translate() takes one or two lengths") }
                let x = try CSSRead.length(CSSRead.single(parts[0])).value
                let y: Double = try parts.count == 2 ? CSSRead.length(CSSRead.single(parts[1])).value : 0
                return .translate(x, y)
            default:
                throw CSSValueError("transform \(name)() is not supported")
            }
        }
    }

    static func animation(_ components: [CSSComponent]) throws -> CSSValue {
        let words = CSSList.words(components)
        if words.count == 1, words[0].lowercasedIdent == "none" { return .keyword("none") }
        guard (2...3).contains(words.count), let name = words[0].lowercasedIdent, animationNames.contains(name) else {
            throw CSSValueError("animation is <name> <duration> [infinite | <count>]; names: bounce, pulse, spin, wiggle")
        }
        let duration = try CSSRead.duration(words[1])
        guard duration > 0 else { throw CSSValueError("an animation needs a duration above 0") }
        var repeatCount: Double? = 1
        if words.count == 3 {
            if words[2].lowercasedIdent == "infinite" {
                repeatCount = nil
            } else {
                let count = try CSSRead.number(words[2])
                guard count > 0 else { throw CSSValueError("an animation repeats at least once") }
                repeatCount = count
            }
        }
        return .animation(name: name, duration: duration, repeatCount: repeatCount)
    }
}
