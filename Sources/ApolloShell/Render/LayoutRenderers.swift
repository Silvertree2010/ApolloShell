import SwiftUI
import ApolloConfig
import ApolloStyle
import ApolloRuntime

@MainActor
enum LayoutRenderers {
    static func flex(horizontal: Bool, style: ComputedStyle, @ViewBuilder content: () -> some View) -> some View {
        let gap = StyleValues.gap(style[horizontal ? "column-gap" : "row-gap"] ?? style["gap"])
        return FlexLayout(horizontal: horizontal, gap: gap, align: StyleValues.keyword(style["align-items"]) ?? "stretch",
                          justify: StyleValues.keyword(style["justify-content"]) ?? "start", definite: Definite(style)) {
            content()
        }
    }

    static func column(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        AnyView(flex(horizontal: false, style: style) { ElementChildren(children: element.children, scope: scope) })
    }

    static func row(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        AnyView(flex(horizontal: true, style: style) { ElementChildren(children: element.children, scope: scope) })
    }

    static func stack(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        AnyView(StackLayout(definite: Definite(style)) { ElementChildren(children: element.children, scope: scope) })
    }

    static func grid(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        AnyView(gridLayout(element, style) { ElementChildren(children: element.children, scope: scope) })
    }

    static func gridLayout(_ element: ElementInstance, _ style: ComputedStyle, @ViewBuilder content: () -> some View) -> some View {
        var columns: [CSSLength]
        if case .gridColumns(let list)? = style["grid-template-columns"] {
            columns = list
        } else {
            let count = max(1, StyleValues.numberValue(element.property("columns")).map(Int.init) ?? 1)
            columns = Array(repeating: CSSLength(1, .fraction), count: count)
        }
        let gap = StyleValues.gap(style["gap"])
        return GridLayout(columns: columns, columnGap: style["column-gap"].map { StyleValues.gap($0) } ?? gap,
                          rowGap: style["row-gap"].map { StyleValues.gap($0) } ?? gap,
                          rowHeight: StyleValues.points(style["grid-auto-rows"]), definite: Definite(style)) {
            content()
        }
    }

    static func reorderable(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        AnyView(ReorderableElement(element: element, style: style, scope: scope))
    }

    static func scroll(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        AnyView(ScrollElement(element: element, style: style, scope: scope))
    }
}

struct ScrollElement: View {
    let element: ElementInstance
    let style: ComputedStyle
    let scope: RenderScope

    var body: some View {
        let horizontal = element.property("axis").plainText == "horizontal"
        let axis: Axis.Set = horizontal ? .horizontal : .vertical
        let indicators = element.property("indicators") == .bool(true)
        let fade = StyleValues.fadeEdges(style["-apollo-fade-edges"])
        let content = VStack(spacing: 0) {
            ElementChildren(children: element.children, scope: scope)
        }
        .frame(maxWidth: horizontal ? nil : .infinity, maxHeight: horizontal ? .infinity : nil)
        ViewThatFits(in: axis) {
            content
                .padding(StyleValues.sides(style["padding"]))
                .onAppear { element.pseudo.remove(.overflowing) }
            ScrollView(axis, showsIndicators: indicators) {
                content.padding(StyleValues.sides(style["padding"]))
            }
            .mask { FadeMask(fraction: fade ?? 0, horizontal: horizontal) }
            .onAppear { element.pseudo.insert(.overflowing) }
        }
    }
}

struct FadeMask: View {
    let fraction: Double
    let horizontal: Bool

    var body: some View {
        LinearGradient(
            stops: [.init(color: .clear, location: 0), .init(color: .black, location: fraction),
                    .init(color: .black, location: 1 - fraction), .init(color: .clear, location: 1)],
            startPoint: horizontal ? .leading : .top, endPoint: horizontal ? .trailing : .bottom
        )
    }
}
