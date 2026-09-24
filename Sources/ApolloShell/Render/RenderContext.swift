import SwiftUI
import ApolloConfig
import ApolloStyle
import ApolloRuntime

@MainActor
final class RenderContext {
    let styles: StyleResolver
    let icons: any AppIconSource
    let trigger: @MainActor (String, Identity, Record) -> Void

    init(styles: StyleResolver, icons: any AppIconSource, trigger: @escaping @MainActor (String, Identity, Record) -> Void) {
        self.styles = styles
        self.icons = icons
        self.trigger = trigger
    }
}

@MainActor
struct RenderScope {
    let context: RenderContext
    let ancestors: [StyleSubject]
    let parentStyle: ComputedStyle?
    let parentKind: String
}

@MainActor
enum ElementRenderers {
    typealias Factory = @MainActor (ElementInstance, ComputedStyle, RenderScope) -> AnyView

    static let table: [String: Factory] = [
        "column": LayoutRenderers.column,
        "row": LayoutRenderers.row,
        "stack": LayoutRenderers.stack,
        "reorderable": LayoutRenderers.reorderable,
        "scroll": LayoutRenderers.scroll,
        "button": ControlRenderers.button,
        "app-icon": ImageRenderers.appIcon,
    ]

    static func view(for element: ElementInstance, style: ComputedStyle, scope: RenderScope) -> AnyView {
        guard let factory = table[element.kind] else { return AnyView(EmptyView()) }
        return factory(element, style, scope)
    }
}

struct ElementView: View {
    let element: ElementInstance
    let scope: RenderScope

    var body: some View {
        let subject = StyleResolver.subject(for: element)
        let style = scope.context.styles.resolve(subject, ancestors: scope.ancestors, parent: scope.parentStyle, inline: element.property("style").plainText)
        let inner = RenderScope(context: scope.context, ancestors: scope.ancestors + [subject], parentStyle: style, parentKind: Self.layoutKind(element))
        if element.property("visible") != .bool(false) {
            let fill = Self.fill(style, parentKind: scope.parentKind, parentStyle: scope.parentStyle)
            ElementRenderers.view(for: element, style: style, scope: inner)
                .modifier(StyledBox(style: style, context: scope.context, padded: element.kind != "scroll", fill: fill))
                .layoutValue(key: ChildMetricsKey.self, value: ChildMetrics(style))
        }
    }
}

extension ElementView {
    static func layoutKind(_ element: ElementInstance) -> String {
        switch element.kind {
        case "reorderable": element.property("axis").plainText == "horizontal" ? "row" : "column"
        default: element.kind
        }
    }

    static func fill(_ style: ComputedStyle, parentKind: String, parentStyle: ComputedStyle?) -> Definite {
        let horizontal: Bool
        switch parentKind {
        case "row": horizontal = true
        case "column": horizontal = false
        default: return Definite()
        }
        let grows = (StyleValues.number(style["flex-grow"]) ?? 0) > 0
        let own = StyleValues.keyword(style["align-self"])
        let inherited = StyleValues.keyword(parentStyle?["align-items"]) ?? "stretch"
        let stretches = (own == nil || own == "auto" ? inherited : own) == "stretch"
        let definite = Definite(style)
        let crossFree = horizontal ? !definite.height : !definite.width
        return horizontal ? Definite(width: grows, height: stretches && crossFree) : Definite(width: stretches && crossFree, height: grows)
    }
}

struct ElementChildren: View {
    let children: [ElementInstance]
    let scope: RenderScope

    var body: some View {
        ForEach(children, id: \.identity) { child in
            ElementView(element: child, scope: scope)
        }
    }
}
