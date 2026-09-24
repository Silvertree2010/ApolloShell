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
    private(set) var lookups = 0
    private(set) var computed = 0
    static let cacheLimit = 4096
    var cachedCount: Int { cache.count }

    let assetRoot: URL?
    let assetRoots: [URL]

    init(sheets: [StyleSheet], environment: StyleEnvironment, assetRoot: URL? = nil) {
        engine = StyleEngine(sheets: sheets)
        self.environment = environment
        self.assetRoot = assetRoot
        assetRoots = sheets.compactMap(\.assetRoot)
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
        let url = URL(fileURLWithPath: path)
        let roots = assetRoots + (assetRoot.map { [$0] } ?? [])
        guard let image = roots.lazy.compactMap({ SafeImageFile.image(at: url, root: $0) }).first else { return nil }
        images[path] = image
        return image
    }

    func parseColor(_ text: String) -> CSSColor? {
        let probe = resolve(StyleSubject(kind: "-apollo-probe"), ancestors: [], parent: nil, inline: "color: \(text)")
        if case .color(let color)? = probe["color"] { return color }
        return nil
    }

    func sensitive(to state: PseudoState, _ subject: StyleSubject, ancestors: [StyleSubject], parent: ComputedStyle?, inline: String?) -> Bool {
        var flipped = subject
        if flipped.pseudo.contains(state) { flipped.pseudo.remove(state) } else { flipped.pseudo.insert(state) }
        return resolve(flipped, ancestors: ancestors, parent: parent, inline: inline) != resolve(subject, ancestors: ancestors, parent: parent, inline: inline)
    }

    func resolve(_ subject: StyleSubject, ancestors: [StyleSubject], parent: ComputedStyle?, inline: String? = nil) -> ComputedStyle {
        let key = Key(subject: subject, ancestors: ancestors, parent: parent, inline: inline ?? "")
        lookups += 1
        if let cached = cache[key] { return cached }
        computed += 1
        var declarations: [Declaration] = []
        if let inline, !inline.isEmpty {
            let parsed = StyleEngine.parseInline(inline, span: .synthetic("style"))
            declarations = parsed.0
            diagnostics += parsed.1
        }
        let (style, found) = engine.computedStyle(for: subject, ancestors: ancestors, parent: parent, inline: declarations, environment: environment)
        diagnostics += found
        cache[key] = style
        return style
    }
}

extension Value {
    var plainText: String? {
        switch self {
        case .string(let text): text.isEmpty ? nil : text
        case .number(let number): number == number.rounded() ? String(Int(number)) : String(number)
        default: nil
        }
    }
}
