struct Specificity: Sendable, Hashable, Comparable {
    var ids = 0
    var classes = 0
    var types = 0

    static func < (lhs: Specificity, rhs: Specificity) -> Bool {
        (lhs.ids, lhs.classes, lhs.types) < (rhs.ids, rhs.classes, rhs.types)
    }

    static func + (lhs: Specificity, rhs: Specificity) -> Specificity {
        Specificity(ids: lhs.ids + rhs.ids, classes: lhs.classes + rhs.classes, types: lhs.types + rhs.types)
    }
}

struct CompoundSelector: Sendable, Hashable {
    var kind: String?
    var id: String?
    var classes: [String] = []
    var pseudo: PseudoState = []
    var isRoot = false

    var specificity: Specificity {
        Specificity(ids: id == nil ? 0 : 1,
                    classes: classes.count + pseudo.rawValue.nonzeroBitCount + (isRoot ? 1 : 0),
                    types: kind == nil ? 0 : 1)
    }

    var isEmpty: Bool { kind == nil && id == nil && classes.isEmpty && pseudo.isEmpty && !isRoot }

    func matches(_ subject: StyleSubject, isRoot subjectIsRoot: Bool) -> Bool {
        if let kind, kind != subject.kind.lowercased() { return false }
        if let id, id != subject.id { return false }
        if !classes.allSatisfy(subject.classes.contains) { return false }
        if !subject.pseudo.isSuperset(of: pseudo) { return false }
        if isRoot, !subjectIsRoot { return false }
        return true
    }
}

enum Combinator: Sendable, Hashable {
    case descendant
    case child
}

struct ComplexSelector: Sendable, Hashable {
    var compounds: [CompoundSelector]
    var combinators: [Combinator]

    var specificity: Specificity {
        compounds.reduce(Specificity()) { $0 + $1.specificity }
    }

    var isBareRoot: Bool {
        compounds.count == 1 && compounds[0] == CompoundSelector(isRoot: true)
    }

    func matches(_ subject: StyleSubject, ancestors: [StyleSubject]) -> Bool {
        guard let last = compounds.last, last.matches(subject, isRoot: ancestors.isEmpty) else { return false }
        return matchAncestors(compoundIndex: compounds.count - 2, limit: ancestors.count, ancestors: ancestors)
    }

    private func matchAncestors(compoundIndex: Int, limit: Int, ancestors: [StyleSubject]) -> Bool {
        guard compoundIndex >= 0 else { return true }
        let compound = compounds[compoundIndex]
        switch combinators[compoundIndex] {
        case .child:
            let candidate = limit - 1
            guard candidate >= 0, compound.matches(ancestors[candidate], isRoot: candidate == 0) else { return false }
            return matchAncestors(compoundIndex: compoundIndex - 1, limit: candidate, ancestors: ancestors)
        case .descendant:
            var candidate = limit - 1
            while candidate >= 0 {
                if compound.matches(ancestors[candidate], isRoot: candidate == 0),
                   matchAncestors(compoundIndex: compoundIndex - 1, limit: candidate, ancestors: ancestors) {
                    return true
                }
                candidate -= 1
            }
            return false
        }
    }
}

enum SelectorParser {
    static func parse(_ components: [CSSComponent]) -> (selectors: [ComplexSelector], problems: [String]) {
        var selectors: [ComplexSelector] = []
        var problems: [String] = []
        for part in CSSList.split(components, by: \.isComma) {
            let text = CSSList.text(part)
            do {
                selectors.append(try complex(CSSList.trimmed(part)))
            } catch {
                let reason = (error as? CSSValueError)?.message ?? "invalid selector"
                problems.append("\(reason) in selector '\(text)'")
            }
        }
        return (selectors, problems)
    }

    private static func complex(_ items: [CSSComponent]) throws -> ComplexSelector {
        guard !items.isEmpty else { throw CSSValueError("empty selector") }
        var groups: [[CSSComponent]] = [[]]
        var combinators: [Combinator] = []
        var pending: Combinator?
        for item in items {
            if item.isWhitespace {
                if pending == nil, !groups[groups.count - 1].isEmpty { pending = .descendant }
                continue
            }
            if let delim = item.delimCharacter, delim == ">" || delim == "+" || delim == "~" {
                guard delim == ">" else { throw CSSValueError("sibling combinators (+, ~) are not supported") }
                guard !groups[groups.count - 1].isEmpty, pending != .child else {
                    throw CSSValueError("'>' needs a selector on both sides")
                }
                pending = .child
                continue
            }
            if let combinator = pending {
                combinators.append(combinator)
                groups.append([])
                pending = nil
            }
            groups[groups.count - 1].append(item)
        }
        guard pending == nil else { throw CSSValueError("'>' needs a selector on both sides") }
        let compounds = try groups.map(compound)
        return ComplexSelector(compounds: compounds, combinators: combinators)
    }

    private static func compound(_ items: [CSSComponent]) throws -> CompoundSelector {
        var result = CompoundSelector()
        var index = 0
        while index < items.count {
            let item = items[index]
            switch item {
            case let .token(token):
                switch token.kind {
                case let .ident(name):
                    guard index == 0 else { throw CSSValueError("a type selector must come first, found '\(name)'") }
                    result.kind = name.lowercased()
                case .delim("*"):
                    guard index == 0 else { throw CSSValueError("'*' must come first") }
                case let .hash(name):
                    guard result.id == nil else { throw CSSValueError("a selector has at most one #id") }
                    result.id = name
                case .delim("."):
                    guard index + 1 < items.count, let name = items[index + 1].ident else {
                        throw CSSValueError("'.' must be followed by a class name")
                    }
                    result.classes.append(name)
                    index += 1
                case .colon:
                    guard index + 1 < items.count else { throw CSSValueError("':' must be followed by a pseudo-class") }
                    let next = items[index + 1]
                    if next.isColon { throw CSSValueError("pseudo-elements are not supported") }
                    if case let .function(name, _, _) = next { throw CSSValueError(":\(name)() is not supported") }
                    guard let name = next.lowercasedIdent else { throw CSSValueError("':' must be followed by a pseudo-class") }
                    if name == "root" {
                        result.isRoot = true
                    } else if let state = PseudoState.byName[name] {
                        result.pseudo.insert(state)
                    } else {
                        throw CSSValueError(":\(name) is not supported")
                    }
                    index += 1
                default:
                    throw CSSValueError("unexpected '\(token.text)'")
                }
            case .block(.bracket, _, _):
                throw CSSValueError("attribute selectors are not supported")
            default:
                throw CSSValueError("unexpected '\(item.text)'")
            }
            index += 1
        }
        return result
    }
}
