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
        let inner = RenderScope(context: scope.context, ancestors: scope.ancestors + [subject], parentStyle: style, parentKind: element.kind)
        if element.property("visible") != .bool(false) {
            ElementRenderers.view(for: element, style: style, scope: inner)
                .modifier(StyledBox(style: style))
                .modifier(SelfAlignment(style: style, parentKind: scope.parentKind))
        }
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

struct StyledBox: ViewModifier {
    let style: ComputedStyle

    func body(content: Content) -> some View {
        let width = style["width"], height = style["height"]
        let shape = RoundedRectangle(cornerRadius: StyleValues.radius(style["border-radius"]), style: StyleValues.keyword(style["-apollo-corner-shape"]) == "circular" ? .circular : .continuous)
        content
            .padding(StyleValues.sides(style["padding"]))
            .frame(width: StyleValues.points(width), height: StyleValues.points(height))
            .frame(maxWidth: StyleValues.fills(width) ? .infinity : nil, maxHeight: StyleValues.fills(height) ? .infinity : nil)
            .background { BackgroundLayers(style: style, shape: shape) }
            .opacity(StyleValues.number(style["opacity"]) ?? 1)
            .offset(StyleValues.translation(style["transform"]))
            .padding(StyleValues.sides(style["margin"]))
    }
}

struct BackgroundLayers<S: Shape>: View {
    let style: ComputedStyle
    let shape: S

    var body: some View {
        if case .layers(let layers)? = style["background"] {
            ZStack {
                ForEach(Array(layers.reversed().enumerated()), id: \.offset) { _, layer in
                    switch layer {
                    case .color(let color):
                        shape.fill(StyleValues.color(color))
                    case .glass, .material:
                        shape.fill(Color(nsColor: .windowBackgroundColor))
                    case .gradient, .image:
                        EmptyView()
                    }
                }
            }
        }
    }
}

struct SelfAlignment: ViewModifier {
    let style: ComputedStyle
    let parentKind: String

    func body(content: Content) -> some View {
        switch (parentKind, StyleValues.keyword(style["align-self"])) {
        case ("stack", "start"?), ("button", "start"?):
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case ("stack", "end"?), ("button", "end"?):
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        case ("column", "start"?), ("reorderable", "start"?):
            content.frame(maxWidth: .infinity, alignment: .leading)
        case ("column", "end"?), ("reorderable", "end"?):
            content.frame(maxWidth: .infinity, alignment: .trailing)
        default:
            content
        }
    }
}
