import ApolloBase
import ApolloShellCore
import Foundation

struct MediaCondition: Sendable, Hashable {
    enum Feature: Sendable, Hashable {
        case colorScheme(Appearance)
        case reducedMotion(Bool)
        case reducedTransparency(Bool)
    }

    var queries: [[Feature]]

    func matches(_ environment: StyleEnvironment) -> Bool {
        queries.contains { features in
            features.allSatisfy { feature in
                switch feature {
                case let .colorScheme(appearance): environment.effectiveAppearance == appearance
                case let .reducedMotion(on): environment.reduceMotion == on
                case let .reducedTransparency(on): environment.reduceTransparency == on
                }
            }
        }
    }

    static func feature(_ words: [CSSComponent]) -> Feature? {
        guard words.count == 3, let name = words[0].lowercasedIdent, words[1].isColon,
              let value = words[2].lowercasedIdent else { return nil }
        switch (name, value) {
        case ("prefers-color-scheme", "dark"): return .colorScheme(.dark)
        case ("prefers-color-scheme", "light"): return .colorScheme(.light)
        case ("prefers-reduced-motion", "reduce"): return .reducedMotion(true)
        case ("prefers-reduced-motion", "no-preference"): return .reducedMotion(false)
        case ("prefers-reduced-transparency", "reduce"): return .reducedTransparency(true)
        case ("prefers-reduced-transparency", "no-preference"): return .reducedTransparency(false)
        default: return nil
        }
    }
}

struct StyleRule: Sendable, Hashable {
    var selectors: [ComplexSelector]
    var declarations: [Declaration]
    var media: [MediaCondition]
    var span: SourceSpan
}

enum CSSWideKeyword: String, Sendable {
    case inherit
    case initial
    case unset

    init?(_ text: String) {
        self.init(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

struct DiagnosticLog {
    let limit: Int
    private var kept: [Diagnostic] = []
    private var dropped = 0

    init(limit: Int) {
        self.limit = max(limit, 2)
    }

    mutating func add(_ diagnostic: Diagnostic) {
        if kept.count < limit {
            kept.append(diagnostic)
        } else {
            dropped += 1
        }
    }

    func finished() -> [Diagnostic] {
        guard dropped > 0 else { return kept }
        let shown = Array(kept.prefix(limit - 1))
        let hidden = kept.count - shown.count + dropped
        return shown + [Diagnostic(.note, "\(hidden) more problems are not shown", span: kept.last?.span, code: .moreHidden)]
    }
}

enum CSSNestingGuard {
    static func firstExcess(_ tokens: [CSSToken]) -> SourcePosition? {
        var depth = 0
        for token in tokens {
            switch token.kind {
            case .function, .openParen, .openBracket, .openBrace:
                if depth == CSSComponentParser.maximumNestingDepth { return token.start }
                depth += 1
            case .closeParen, .closeBracket, .closeBrace:
                if depth > 0 { depth -= 1 }
            default:
                break
            }
        }
        return nil
    }
}

public struct StyleSheet: Sendable, Hashable {
    public var origin: StyleOrigin
    public var file: String
    public internal(set) var assetRoot: URL?
    var rules: [StyleRule]

    public static let maximumBytes = 512 * 1024
    public static let maximumRules = 8192
    public static let maximumDiagnostics = 200

    public func fallbackProblems() -> [Diagnostic] {
        let context = CSSParseContext(assetRoot: assetRoot)
        var found: [Diagnostic] = []
        for rule in rules {
            for d in rule.declarations where !d.property.hasPrefix("--") && CSSVariables.containsVar(d.rawValue) {
                guard let text = try? CSSVariables.substitute(d.rawValue, lookup: { _ in nil }), CSSWideKeyword(text) == nil else { continue }
                do {
                    _ = try CSSPropertyRegistry.parse(d.property, text, context: context)
                } catch {
                    let reason = (error as? CSSValueError)?.message ?? "unreadable value"
                    found.append(Diagnostic(.warning, "the var() fallback of '\(d.property)' is not valid: \(reason)", span: d.span, code: .styleValue))
                }
            }
        }
        return found
    }

    public static func parse(_ text: String, file: String, origin: StyleOrigin) -> (StyleSheet, [Diagnostic]) {
        parse(text, file: file, origin: origin, assetRoot: nil)
    }

    public static func parse(_ text: String, file: String, origin: StyleOrigin, assetRoot: URL?) -> (StyleSheet, [Diagnostic]) {
        var sheet = StyleSheet(origin: origin, file: file, assetRoot: assetRoot, rules: [])
        let bytes = text.utf8.count
        guard bytes <= maximumBytes else {
            let start = SourcePosition(offset: 0, line: 1, column: 1)
            let diagnostic = Diagnostic(.error, "style sheet is \(bytes) bytes, the limit is \(maximumBytes); it is not used",
                                        span: SourceSpan(file: file, start: start, end: start), code: .styleTooLarge)
            return (sheet, [diagnostic])
        }
        var parser = StyleSheetParser(file: file, context: CSSParseContext(assetRoot: assetRoot))
        let (tokens, problems) = CSSTokenizer.tokenize(text)
        for problem in problems {
            parser.log.add(Diagnostic(.warning, problem.message,
                                      span: SourceSpan(file: file, start: problem.position, end: problem.position), code: .styleSyntax))
        }
        if let excess = CSSNestingGuard.firstExcess(tokens) {
            parser.log.add(Diagnostic(.warning,
                "nesting is deeper than \(CSSComponentParser.maximumNestingDepth) levels; the deeper parts are read as flat text",
                span: SourceSpan(file: file, start: excess, end: excess), code: .styleNesting))
        }
        parser.ruleList(CSSComponentParser.parse(tokens), media: [])
        sheet.rules = parser.rules
        return (sheet, parser.log.finished())
    }

    public var declaredProperties: Set<String> {
        Set(rules.flatMap { $0.declarations.map(\.property) })
    }

    public var selectorPseudo: PseudoState {
        rules.flatMap(\.selectors).flatMap(\.compounds).reduce(into: PseudoState()) { $0.formUnion($1.pseudo) }
    }

    public var declaredCustomProperties: Set<String> {
        var names: Set<String> = []
        for rule in rules where rule.selectors.contains(where: \.isBareRoot) {
            for declaration in rule.declarations where declaration.property.hasPrefix("--") {
                names.insert(declaration.property)
            }
        }
        return names
    }
}

struct StyleSheetParser {
    let file: String
    let context: CSSParseContext
    var rules: [StyleRule] = []
    var log = DiagnosticLog(limit: StyleSheet.maximumDiagnostics)
    var fixedSpan: SourceSpan?
    private var ruleLimitReported = false

    init(file: String, context: CSSParseContext) {
        self.file = file
        self.context = context
    }

    static func inline(_ text: String, span: SourceSpan, context: CSSParseContext) -> ([Declaration], [Diagnostic]) {
        var parser = StyleSheetParser(file: span.file, context: context)
        parser.fixedSpan = span
        let (tokens, problems) = CSSTokenizer.tokenize(text)
        for problem in problems { parser.log.add(Diagnostic(.warning, problem.message, span: span, code: .styleSyntax)) }
        if let excess = CSSNestingGuard.firstExcess(tokens) {
            _ = excess
            parser.log.add(Diagnostic(.warning,
                "nesting is deeper than \(CSSComponentParser.maximumNestingDepth) levels; the deeper parts are read as flat text",
                span: span, code: .styleNesting))
        }
        let declarations = parser.declarationList(CSSComponentParser.parse(tokens))
        return (declarations, parser.log.finished())
    }

    func span(_ components: [CSSComponent]) -> SourceSpan {
        if let fixedSpan { return fixedSpan }
        let items = CSSList.trimmed(components)
        guard let first = items.first, let last = items.last else {
            let start = SourcePosition(offset: 0, line: 1, column: 1)
            return SourceSpan(file: file, start: start, end: start)
        }
        return SourceSpan(file: file, start: first.start, end: last.end)
    }

    mutating func warn(_ message: String, _ components: [CSSComponent], help: String? = nil) {
        log.add(Diagnostic(.warning, message, span: span(components), help: help, code: .styleValue))
    }

    mutating func ruleList(_ components: [CSSComponent], media: [MediaCondition]) {
        var prelude: [CSSComponent] = []
        for component in components {
            if case let .block(.brace, contents, _) = component {
                rule(prelude: prelude, block: contents, blockComponent: component, media: media)
                prelude = []
                continue
            }
            if component.isSemicolon {
                statement(prelude)
                prelude = []
                continue
            }
            if prelude.isEmpty, component.isWhitespace { continue }
            prelude.append(component)
        }
        if !CSSList.words(prelude).isEmpty {
            warn("'\(CSSList.text(prelude))' has no block and is ignored", prelude)
        }
    }

    private mutating func statement(_ prelude: [CSSComponent]) {
        guard let first = CSSList.words(prelude).first else { return }
        if case let .atKeyword(name)? = first.tokenKind {
            warn("@\(name) is not supported and is ignored", prelude)
            return
        }
        warn("'\(CSSList.text(prelude))' is outside a rule and is ignored", prelude)
    }

    private mutating func rule(prelude: [CSSComponent], block: [CSSComponent], blockComponent: CSSComponent, media: [MediaCondition]) {
        guard let first = CSSList.words(prelude).first else {
            warn("a block without a selector is ignored", [blockComponent])
            return
        }
        if case let .atKeyword(name)? = first.tokenKind {
            let condition = Array(prelude.dropFirst())
            guard name.lowercased() == "media" else {
                warn("@\(name) is not supported; the block is ignored", prelude)
                return
            }
            guard let parsed = StyleSheetParser.mediaCondition(condition) else {
                warn("@media \(CSSList.text(condition)) is not supported; the block is ignored", prelude)
                return
            }
            ruleList(block, media: media + [parsed])
            return
        }
        guard rules.count < StyleSheet.maximumRules else {
            if !ruleLimitReported {
                warn("more than \(StyleSheet.maximumRules) rules; the rest is ignored", prelude)
                ruleLimitReported = true
            }
            return
        }
        let parsed = SelectorParser.parse(prelude)
        for problem in parsed.problems { warn(problem + "; this selector is ignored", prelude) }
        guard !parsed.selectors.isEmpty else { return }
        let declarations = declarationList(block)
        rules.append(StyleRule(selectors: parsed.selectors, declarations: declarations, media: media, span: span(prelude)))
    }

    static func mediaCondition(_ components: [CSSComponent]) -> MediaCondition? {
        var queries: [[MediaCondition.Feature]] = []
        for words in CSSList.commaSeparated(components) {
            guard !words.isEmpty else { return nil }
            var features: [MediaCondition.Feature] = []
            var expectFeature = true
            for word in words {
                if expectFeature {
                    if word.lowercasedIdent == "all", features.isEmpty {
                        expectFeature = false
                        continue
                    }
                    guard case let .block(.paren, contents, _) = word,
                          let feature = MediaCondition.feature(CSSList.words(contents)) else { return nil }
                    features.append(feature)
                    expectFeature = false
                } else {
                    guard word.lowercasedIdent == "and" else { return nil }
                    expectFeature = true
                }
            }
            guard !expectFeature else { return nil }
            queries.append(features)
        }
        return queries.isEmpty ? nil : MediaCondition(queries: queries)
    }

    mutating func declarationList(_ components: [CSSComponent]) -> [Declaration] {
        var result: [Declaration] = []
        for part in CSSList.split(components, by: \.isSemicolon) {
            let items = CSSList.trimmed(part)
            guard !items.isEmpty else { continue }
            if let declaration = declaration(items) { result.append(declaration) }
        }
        return result
    }

    private mutating func declaration(_ items: [CSSComponent]) -> Declaration? {
        let nested = items.contains { component in
            if case .block(.brace, _, _) = component { return true }
            return false
        }
        guard let rawName = items[0].ident else {
            warn(nested ? "nested rules are not supported" : "expected a property name, found '\(items[0].text)'", items)
            return nil
        }
        let rest = Array(items.dropFirst().drop(while: \.isWhitespace))
        guard let colon = rest.first, colon.isColon, !nested else {
            warn(nested ? "nested rules are not supported" : "expected ':' after '\(rawName)'", items)
            return nil
        }
        var value = CSSList.trimmed(Array(rest.dropFirst()))
        var important = false
        if let last = value.last, last.lowercasedIdent == "important" {
            var bang = value.count - 2
            while bang >= 0, value[bang].isWhitespace { bang -= 1 }
            if bang >= 0, value[bang].delimCharacter == "!" {
                important = true
                value = CSSList.trimmed(Array(value[..<bang]))
            }
        }
        let name = rawName.hasPrefix("--") ? rawName : rawName.lowercased()
        let rawValue = value.map(\.text).joined()
        let declarationSpan = span(items)
        if name.hasPrefix("--") {
            if name.lowercased().hasPrefix(ThemeTokenCatalog.prefix) {
                warn("\(name) belongs to themes; a style sheet can read it with var() but not set it", items)
                return nil
            }
            return Declaration(property: name, rawValue: rawValue, important: important, span: declarationSpan)
        }
        guard CSSPropertyRegistry.builtin[name] != nil else {
            let suggestion = Suggestion.closest(to: name, among: CSSPropertyRegistry.builtin.keys.sorted())
            warn("unknown property '\(name)'; the declaration is ignored", items, help: suggestion.map { "did you mean '\($0)'?" })
            return nil
        }
        guard !value.isEmpty else {
            warn("'\(name)' has no value", items)
            return nil
        }
        if !CSSVariables.containsVar(rawValue), CSSWideKeyword(rawValue) == nil {
            do {
                _ = try CSSPropertyRegistry.parse(name, rawValue, context: context)
            } catch {
                warn("invalid value for '\(name)': \((error as? CSSValueError)?.message ?? "unreadable value")", items)
                return nil
            }
        }
        return Declaration(property: name, rawValue: rawValue, important: important, span: declarationSpan)
    }
}
