import Foundation
import AppKit
import ApolloBase
import ApolloConfig
import ApolloStyle
import ApolloRuntime

@MainActor
final class StyleResolver {
    struct Key: Hashable {
        var subject: StyleSubject
        var ancestors: [StyleSubject]
        var parent: ComputedStyle?
        var inline: String
    }

    let engine: StyleEngine
    let environment: StyleEnvironment
    private var cache = BoundedCache<Key, ComputedStyle>(limit: StyleResolver.cacheLimit)
    private(set) var diagnostics: [Diagnostic] = []
    private var seenDiagnostics: Set<Diagnostic> = []
    private(set) var lookups = 0
    private(set) var computed = 0
    private(set) static var computedTotal = 0
    static let cacheLimit = 4096
    static let diagnosticLimit = 256
    var cachedCount: Int { cache.count }

    let assetRoot: URL?
    let assetRoots: [URL]
    let declared: Set<String>
    let selectorPseudo: PseudoState

    init(sheets: [StyleSheet], environment: StyleEnvironment, assetRoot: URL? = nil) {
        engine = StyleEngine(sheets: sheets)
        self.environment = environment
        self.assetRoot = assetRoot
        assetRoots = (sheets.compactMap(\.assetRoot) + (assetRoot.map { [$0] } ?? [])).map { $0.resolvingSymlinksInPath().standardizedFileURL }
        declared = sheets.reduce(into: Set<String>()) { $0.formUnion($1.declaredProperties) }
        selectorPseudo = sheets.reduce(into: PseudoState()) { $0.formUnion($1.selectorPseudo) }
    }

    static func subject(for element: ElementInstance) -> StyleSubject {
        StyleSubject(kind: element.kind, id: element.property("id").plainText, classes: classes(element.property("class")), pseudo: element.pseudo)
    }

    static func subject(for surface: SurfaceInstance) -> StyleSubject {
        StyleSubject(kind: surface.ir.kind, id: surface.id, classes: classes(surface.property("class")), pseudo: surface.isOpen ? .open : [])
    }

    static func classes(_ value: Value) -> [String] {
        guard let text = value.plainText else { return [] }
        return text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private var images = BoundedCache<String, NSImage>(limit: 128)

    func image(_ path: String) -> NSImage? {
        if let cached = images[path] { return cached }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard let root = assetRoots.filter({ url.path.hasPrefix($0.path + "/") }).max(by: { $0.path.count < $1.path.count }),
              let image = SafeImageFile.image(at: url, root: root)
        else { return nil }
        images[path] = image
        return image
    }

    func parseColor(_ text: String) -> CSSColor? {
        let probe = resolve(StyleSubject(kind: "-apollo-probe"), ancestors: [], parent: nil, inline: "color: \(text)")
        if case .color(let color)? = probe["color"] { return color }
        return nil
    }

    private struct SlotKey: Hashable {
        var probe: String
        var subject: StaticSubject
    }
    private var slots: [SlotKey: Bool] = [:]

    func declares(_ property: String, _ subject: StaticSubject) -> Bool {
        guard declared.contains(property) else { return false }
        return slot(SlotKey(probe: property, subject: subject)) { engine.mayDeclare(property, subject) }
    }

    func declaresAny(_ properties: [String], _ subject: StaticSubject, includingNone: Bool = false) -> Bool {
        slot(SlotKey(probe: (includingNone ? "+" : "=") + properties.joined(separator: ","), subject: subject)) {
            engine.mayDeclare(anyOf: properties, subject, includingNone: includingNone)
        }
    }

    private var partsCache: [StaticSubject: BoxParts] = [:]

    func parts(_ subject: StaticSubject) -> BoxParts {
        if let known = partsCache[subject] { return known }
        let made = BoxParts(styles: self, subject: subject)
        partsCache[subject] = made
        return made
    }

    private var inlineCache = BoundedCache<String, InlineUse>(limit: 512)

    func inlineUse(_ text: String?) -> InlineUse {
        guard let text, !text.isEmpty else { return InlineUse(parts: BoxParts(names: []), filter: false, animation: false) }
        if let known = inlineCache[text] { return known }
        let names = StyleEngine.parseInline(text, span: .synthetic("style")).0.map { $0.property.lowercased() }
        let made = InlineUse(parts: BoxParts(names: names), filter: names.contains { $0 == "filter" || $0.hasPrefix("filter-") },
                             animation: names.contains { $0 == "animation" || $0.hasPrefix("animation-") })
        inlineCache[text] = made
        return made
    }

    func stateStyled(_ state: PseudoState, _ subject: StaticSubject) -> Bool {
        guard !selectorPseudo.isDisjoint(with: state) else { return false }
        return slot(SlotKey(probe: ":\(state.rawValue)", subject: subject)) { engine.mayMatch(state, subject) }
    }

    private func slot(_ key: SlotKey, _ compute: () -> Bool) -> Bool {
        if let known = slots[key] { return known }
        let found = compute()
        slots[key] = found
        return found
    }

    static func staticSubject(for element: ElementInstance) -> StaticSubject {
        staticSubject(kind: element.kind, id: element.ir.properties["id"], classes: element.ir.properties["class"])
    }

    static func staticSubject(for surface: SurfaceInstance) -> StaticSubject {
        var subject = staticSubject(kind: surface.ir.kind, id: nil, classes: surface.ir.properties["class"])
        subject.id = surface.id
        return subject
    }

    static func staticSubject(kind: String, id: CompiledValue?, classes: CompiledValue?) -> StaticSubject {
        var subject = StaticSubject(kind: kind)
        if let id {
            if case .literal(let text) = id.template { subject.id = text } else if case .whole(.literal(let value)) = id.template { subject.id = value.plainText } else { subject.anyID = true }
        }
        if let classes, let words = ClassCandidates.words(classes.template) {
            subject.classes = words
        } else if classes != nil {
            subject.anyClass = true
        }
        return subject
    }

    func resolve(_ subject: StyleSubject, ancestors: [StyleSubject], parent: ComputedStyle?, inline: String? = nil) -> ComputedStyle {
        let key = Key(subject: subject, ancestors: ancestors, parent: parent, inline: inline ?? "")
        lookups += 1
        if let cached = cache[key] { return cached }
        computed += 1
        Self.computedTotal += 1
        var declarations: [Declaration] = []
        if let inline, !inline.isEmpty {
            let parsed = StyleEngine.parseInline(inline, span: .synthetic("style"))
            declarations = parsed.0
            note(parsed.1)
        }
        let (style, found) = engine.computedStyle(for: subject, ancestors: ancestors, parent: parent, inline: declarations, environment: environment)
        note(found)
        cache[key] = style
        return style
    }

    private func note(_ found: [Diagnostic]) {
        for diagnostic in found where diagnostics.count < Self.diagnosticLimit && seenDiagnostics.insert(diagnostic).inserted {
            diagnostics.append(diagnostic)
        }
    }
}

extension Value {
    var plainText: String? {
        switch self {
        case .string(let text): text.isEmpty ? nil : text
        case .number(let number): number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
        default: nil
        }
    }
}

enum ClassCandidates {
    static func words(_ template: StringTemplate) -> Set<String>? {
        switch template {
        case .literal(let text): return split(text)
        case .whole(let expr): return words(expr)
        case .parts(let parts):
            var found: Set<String> = []
            for (index, part) in parts.enumerated() {
                switch part {
                case .text(let text):
                    found.formUnion(split(text))
                case .expression(let expr):
                    guard let inner = words(expr) else { return nil }
                    if index > 0, case .text(let before) = parts[index - 1], before.last.map({ !$0.isWhitespace }) ?? false { return nil }
                    if index + 1 < parts.count, case .text(let after) = parts[index + 1], after.first.map({ !$0.isWhitespace }) ?? false { return nil }
                    found.formUnion(inner)
                }
            }
            return found
        }
    }

    static func words(_ expr: Expr) -> Set<String>? {
        switch expr {
        case .literal(let value):
            switch value {
            case .string(let text): return split(text)
            case .null, .bool: return []
            default: return nil
            }
        case .conditional(_, let then, let otherwise), .coalesce(let then, let otherwise):
            guard let first = words(then), let second = words(otherwise) else { return nil }
            return first.union(second)
        default:
            return nil
        }
    }

    static func split(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: \.isWhitespace).map(String.init))
    }
}

extension StyleResolver {
    func resolve(surface: SurfaceInstance) -> ComputedStyle {
        resolve(Self.subject(for: surface), ancestors: [], parent: nil, inline: surface.property("style").plainText)
    }
}
