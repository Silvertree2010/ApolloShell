import Foundation
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
    private var cache: [Key: ComputedStyle] = [:]
    private(set) var diagnostics: [Diagnostic] = []

    init(sheets: [StyleSheet], environment: StyleEnvironment) {
        engine = StyleEngine(sheets: sheets)
        self.environment = environment
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

    func resolve(_ subject: StyleSubject, ancestors: [StyleSubject], parent: ComputedStyle?, inline: String? = nil) -> ComputedStyle {
        let key = Key(subject: subject, ancestors: ancestors, parent: parent, inline: inline ?? "")
        if let cached = cache[key] { return cached }
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
