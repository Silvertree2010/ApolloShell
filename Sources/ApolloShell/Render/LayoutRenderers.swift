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
            let count = max(1, StyleValues.count(element.property("columns"), limit: 1000) ?? 1)
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
        let both = element.property("axis").plainText == "both"
        let axis: Axis.Set = both ? [.horizontal, .vertical] : horizontal ? .horizontal : .vertical
        let indicators = element.property("indicators") == .bool(true)
        let fade = StyleValues.fadeEdges(style["-apollo-fade-edges"])
        let overflowing = element.pseudo.contains(.overflowing)
        let gap = style["gap"].map { StyleValues.gap($0) } ?? 0
        let reveal = element.property("reveal")
        ScrollFit(horizontal: horizontal, fills: StyleValues.keyword(style["justify-content"]) == "start") {
            ScrollViewReader { proxy in
                ScrollView(axis, showsIndicators: indicators) {
                    Group {
                        if horizontal {
                            HStack(spacing: gap) { ElementChildren(children: element.children, scope: scope) }
                        } else {
                            VStack(spacing: gap) { ElementChildren(children: element.children, scope: scope) }
                        }
                    }
                    .frame(maxWidth: horizontal || both ? nil : .infinity, maxHeight: horizontal ? .infinity : nil)
                    .padding(StyleValues.sides(style["padding"]))
                    .environment(\.revealScope, element.ir.properties["reveal"] != nil)
                }
                .onChange(of: reveal) { _, target in
                    guard target != .null else { return }
                    proxy.scrollTo(target)
                }
                .onAppear {
                    guard reveal != .null else { return }
                    proxy.scrollTo(reveal)
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: axis)
            .scrollClipDisabled(!overflowing)
            .modifier(HitRegionClip(active: true))
            .modifier(HitRegionMarker(active: overflowing, identity: element.identity))
            .onScrollGeometryChange(for: Bool.self) { geometry in
                (horizontal || both) && geometry.contentSize.width > geometry.containerSize.width + 0.5
                    || !horizontal && geometry.contentSize.height > geometry.containerSize.height + 0.5
            } action: { _, now in
                if now { element.pseudo.insert(.overflowing) } else { element.pseudo.remove(.overflowing) }
            }
            .mask {
                if overflowing, let fade, fade > 0 {
                    FadeMask(fraction: fade, horizontal: horizontal)
                } else {
                    Rectangle().padding(-100_000)
                }
            }
        }
    }
}

struct RevealID: ViewModifier {
    let element: ElementInstance
    @Environment(\.revealScope) private var revealScope

    func body(content: Content) -> some View {
        if revealScope, let id = Self.id(element) {
            content.id(id)
        } else {
            content
        }
    }

    static func id(_ element: ElementInstance) -> Value? {
        if let key = element.entryKey { return key }
        if case .string(let id) = element.property("id"), !id.isEmpty { return .string(id) }
        return nil
    }
}

private struct RevealScopeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var revealScope: Bool {
        get { self[RevealScopeKey.self] }
        set { self[RevealScopeKey.self] = newValue }
    }
}

struct ScrollFit: GuideFreeLayout {
    let horizontal: Bool
    var fills = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let fitted = subview.sizeThatFits(proposal)
        if fills { return fitted }
        let ideal = subview.sizeThatFits(horizontal ? ProposedViewSize(width: nil, height: proposal.height) : ProposedViewSize(width: proposal.width, height: nil))
        return horizontal ? CGSize(width: min(fitted.width, ideal.width), height: fitted.height)
            : CGSize(width: fitted.width, height: min(fitted.height, ideal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
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
