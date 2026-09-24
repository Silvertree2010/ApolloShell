import ApolloBase
import ApolloShellCore

struct CascadeRank: Sendable, Hashable, Comparable {
    var important: Bool
    var origin: StyleOrigin
    var specificity: Specificity
    var position: Int

    static func < (lhs: CascadeRank, rhs: CascadeRank) -> Bool {
        if lhs.important != rhs.important { return !lhs.important }
        if lhs.origin != rhs.origin { return lhs.origin < rhs.origin }
        if lhs.specificity != rhs.specificity { return lhs.specificity < rhs.specificity }
        return lhs.position < rhs.position
    }
}

struct CascadeCandidate: Sendable {
    var declaration: Declaration
    var rank: CascadeRank
    var fromBareRoot: Bool
    var context: CSSParseContext
}

struct DiagnosticCollector {
    private var seen: Set<Diagnostic> = []
    private(set) var list: [Diagnostic] = []

    mutating func add(_ diagnostic: Diagnostic) {
        if seen.insert(diagnostic).inserted { list.append(diagnostic) }
    }
}

public final class StyleEngine: Sendable {
    let sheets: [StyleSheet]

    public init(sheets: [StyleSheet]) {
        self.sheets = sheets
    }

    public static func parseInline(_ text: String, span: SourceSpan) -> ([Declaration], [Diagnostic]) {
        StyleSheetParser.inline(text, span: span, context: CSSParseContext())
    }

    public func computedStyle(for subject: StyleSubject, ancestors: [StyleSubject], parent: ComputedStyle?,
                              inline: [Declaration], environment: StyleEnvironment) -> (ComputedStyle, [Diagnostic]) {
        var diagnostics = DiagnosticCollector()
        let candidates = collect(subject: subject, ancestors: ancestors, inline: inline, environment: environment)
        let tokens = environment.tokens

        var own: [String: String] = [:]
        var customSpans: [String: SourceSpan] = [:]
        for (name, list) in candidates where name.hasPrefix("--") {
            guard let winner = list.max(by: { $0.rank < $1.rank }) else { continue }
            customSpans[name] = winner.declaration.span
            if winner.fromBareRoot, let themed = tokens.value(name) {
                own[name] = themed
            } else {
                own[name] = winner.declaration.rawValue
            }
        }
        let resolver = CustomPropertyResolver(own: own, inherited: parent?.customProperties ?? [:], tokens: tokens)
        let custom = resolver.resolveAll()
        for failure in resolver.failures {
            diagnostics.add(Diagnostic(.warning, "custom property \(failure.name) is invalid: \(failure.message)",
                                       span: customSpans[failure.name]))
        }
        let lookup: (String) -> String? = { name in
            name.lowercased().hasPrefix(ThemeTokenCatalog.prefix) ? tokens.value(name) : custom[name]
        }

        var values: [String: CSSValue] = [:]
        var winners: [String: CascadeRank] = [:]
        var declared: Set<String> = []
        for (name, list) in candidates where !name.hasPrefix("--") {
            guard let schema = CSSPropertyRegistry.builtin[name] else { continue }
            attempts: for candidate in list.sorted(by: { $0.rank > $1.rank }) {
                do {
                    let text = try CSSVariables.substitute(candidate.declaration.rawValue, lookup: lookup)
                    switch CSSWideKeyword(text) {
                    case .inherit?:
                        if let inherited = parent?[name] { values[name] = inherited }
                    case .initial?:
                        if let initial = schema.initial { values[name] = initial }
                    case .unset?:
                        if schema.inherits, let inherited = parent?[name] {
                            values[name] = inherited
                        } else if let initial = schema.initial {
                            values[name] = initial
                        }
                    case nil:
                        values[name] = try CSSPropertyRegistry.parse(name, text, context: candidate.context)
                        declared.insert(name)
                    }
                    winners[name] = candidate.rank
                    break attempts
                } catch {
                    let reason = (error as? CSSValueError)?.message ?? "unreadable value"
                    diagnostics.add(Diagnostic(.warning, "invalid value for '\(name)': \(reason)", span: candidate.declaration.span))
                }
            }
        }
        for (name, schema) in CSSPropertyRegistry.builtin where values[name] == nil {
            if schema.inherits, let inherited = parent?[name] {
                values[name] = inherited
            } else if let initial = schema.initial {
                values[name] = initial
            }
        }
        StyleFinisher.finish(&values, winners: winners, declared: declared, environment: environment)
        var style = ComputedStyle(values: values)
        style.customProperties = custom
        return (style, diagnostics.list)
    }

    private func collect(subject: StyleSubject, ancestors: [StyleSubject], inline: [Declaration],
                         environment: StyleEnvironment) -> [String: [CascadeCandidate]] {
        var result: [String: [CascadeCandidate]] = [:]
        var position = 0
        for sheet in sheets {
            let context = CSSParseContext(assetRoot: sheet.assetRoot)
            for rule in sheet.rules where rule.media.allSatisfy({ $0.matches(environment) }) {
                let matching = rule.selectors.filter { $0.matches(subject, ancestors: ancestors) }
                guard let best = matching.max(by: { $0.specificity < $1.specificity }) else { continue }
                let bareRoot = matching.contains(where: \.isBareRoot)
                for declaration in rule.declarations {
                    position += 1
                    let rank = CascadeRank(important: declaration.important, origin: sheet.origin,
                                           specificity: best.specificity, position: position)
                    result[declaration.property, default: []].append(
                        CascadeCandidate(declaration: declaration, rank: rank, fromBareRoot: bareRoot, context: context))
                }
            }
        }
        let inlineContext = CSSParseContext()
        for declaration in inline where !declaration.property.lowercased().hasPrefix(ThemeTokenCatalog.prefix) {
            position += 1
            let rank = CascadeRank(important: declaration.important, origin: .inline, specificity: Specificity(), position: position)
            result[declaration.property, default: []].append(
                CascadeCandidate(declaration: declaration, rank: rank, fromBareRoot: false, context: inlineContext))
        }
        return result
    }
}
