import SwiftUI
import ApolloConfig
import ApolloStyle
import ApolloRuntime

@MainActor
enum LayoutRenderers {
    static func column(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        AnyView(VStack(alignment: StyleValues.horizontal(style["align-items"]), spacing: StyleValues.gap(style["gap"])) {
            ElementChildren(children: element.children, scope: scope)
        })
    }

    static func row(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        AnyView(HStack(alignment: StyleValues.vertical(style["align-items"]), spacing: StyleValues.gap(style["gap"])) {
            ElementChildren(children: element.children, scope: scope)
        })
    }

    static func stack(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        AnyView(ZStack {
            ElementChildren(children: element.children, scope: scope)
        })
    }

    static func reorderable(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        if element.property("axis").plainText == "horizontal" {
            return row(element, style, scope)
        }
        return column(element, style, scope)
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
