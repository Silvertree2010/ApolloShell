import SwiftUI
import AppKit
import ApolloConfig
import ApolloStyle
import ApolloRuntime
import ApolloShellCore

@MainActor
enum MenuBarRenderers {
    static func appMenus(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        let shown = element.children.filter { $0.kind != "flyout" }
        let keys = shown.map { $0.entryKey ?? .null }
        let overflow = shown.count > 1 ? shown.last?.identity : nil
        let context = scope.context
        let gap = StyleValues.gap(style["column-gap"] ?? style["gap"])
        return AnyView(AppMenusLayout(spacing: gap, report: { hidden in
            guard let overflow else { return }
            let values = hidden.map { keys[$0] }
            if context.menuOverflow[overflow] != values { context.menuOverflow[overflow] = values }
        }) {
            ElementChildren(children: element.children, scope: scope)
        })
    }
}

struct AppMenusLayout: Layout {
    var spacing: CGFloat
    var report: @MainActor ([Int]) -> Void

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: nil, height: proposal.height)) }
        let height = sizes.map(\.height).max() ?? 0
        let counted = subviews.count > 1 ? sizes.dropLast() : sizes[...]
        let natural = counted.reduce(0) { $0 + $1.width } + CGFloat(max(counted.count - 1, 0)) * spacing
        guard let width = proposal.width, width.isFinite else { return CGSize(width: natural, height: height) }
        return CGSize(width: min(width, natural), height: height)
    }

    static func fit(widths: [Double], available: Double, spacing: Double) -> (shown: Set<Int>, hidden: [Int]) {
        guard widths.count > 1 else { return (Set(widths.indices), []) }
        let titles = Array(widths.dropFirst().dropLast())
        let fit = AppMenuCollapse.fit(available: available, lead: widths[0], titles: titles, overflow: widths.last ?? 0, spacing: spacing)
        var shown: Set<Int> = [0]
        for index in 0..<fit.shown { shown.insert(index + 1) }
        if fit.overflow { shown.insert(widths.count - 1) }
        let hidden = fit.overflow ? Array((fit.shown + 1)..<(widths.count - 1)) : []
        return (shown, hidden)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let proposals = subviews.map { $0.sizeThatFits(ProposedViewSize(width: nil, height: bounds.height)) }
        let widths = proposals.map { Double($0.width) }
        let result = Self.fit(widths: widths, available: Double(proposal.width ?? bounds.width), spacing: Double(spacing))
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            if result.shown.contains(index) {
                subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: proposals[index].width, height: bounds.height))
                x += proposals[index].width + spacing
            } else {
                subview.place(at: CGPoint(x: -100_000, y: bounds.midY), anchor: .leading, proposal: .unspecified)
            }
        }
        let hidden = result.hidden
        let report = report
        MainActor.assumeIsolated { report(hidden) }
    }
}

struct ZoneRow {
    var gap: CGFloat
    var align: String
    var notch: BarNotch?

    enum Zone { case start, center, end }

    static func zone(_ metrics: ChildMetrics) -> Zone {
        switch metrics.justifySelf {
        case "center": .center
        case "end": .end
        default: .start
        }
    }

    static func applies(_ metrics: [ChildMetrics]) -> Bool {
        metrics.contains { zone($0) != .start }
    }

    func place(in bounds: CGRect, subviews: LayoutSubviews) {
        let metrics = subviews.map { $0[ChildMetricsKey.self] }
        let naturals = subviews.map { $0.sizeThatFits(ProposedViewSize(width: nil, height: bounds.height)).width }
        var groups: [Zone: [Int]] = [.start: [], .center: [], .end: []]
        for index in subviews.indices { groups[Self.zone(metrics[index]), default: []].append(index) }
        func natural(_ zone: Zone) -> CGFloat {
            let members = groups[zone] ?? []
            return members.reduce(0) { $0 + (metrics[$1].grow > 0 ? 0 : naturals[$1]) } + CGFloat(max(members.count - 1, 0)) * gap
        }
        func flexible(_ zone: Zone) -> Int {
            (groups[zone] ?? []).reduce(0) { $0 + (metrics[$1].grow > 0 ? max(1, Int(metrics[$1].grow.rounded())) : 0) }
        }
        let placement = MenuBarZoneLayout.place(
            length: bounds.width, start: natural(.start), center: natural(.center), end: natural(.end), gap: gap,
            notch: notch, flexible: .init(start: flexible(.start), center: flexible(.center), end: flexible(.end))
        )
        for (zone, span) in [(Zone.start, placement.start), (.center, placement.center), (.end, placement.end)] {
            let members = groups[zone] ?? []
            let spans = MenuBarZoneLayout.stack(naturals: members.map { metrics[$0].grow > 0 ? 0 : naturals[$0] },
                                                weights: members.map { metrics[$0].grow > 0 ? max(1, Int(metrics[$0].grow.rounded())) : 0 },
                                                length: span.length, spacing: gap)
            for (member, inner) in zip(members, spans) {
                let subview = subviews[member]
                let length = min(inner.length, max(span.end - span.origin - inner.origin, 0))
                let measured = subview.sizeThatFits(ProposedViewSize(width: length, height: bounds.height))
                let own = metrics[member].alignSelf.flatMap { $0 == "auto" ? nil : $0 } ?? align
                let y: CGFloat
                switch own {
                case "start", "stretch": y = bounds.minY
                case "end": y = bounds.maxY - measured.height
                default: y = bounds.minY + (bounds.height - measured.height) / 2
                }
                subview.place(at: CGPoint(x: bounds.minX + span.origin + inner.origin, y: y), anchor: .topLeading,
                              proposal: ProposedViewSize(width: length, height: own == "stretch" ? bounds.height : measured.height))
            }
        }
    }
}

struct NotchRow: View {
    let element: ElementInstance
    let style: ComputedStyle
    let scope: RenderScope
    @State private var origin: CGFloat = 0

    var body: some View {
        LayoutRenderers.flex(horizontal: true, style: style, notch: notch) {
            ElementChildren(children: element.children, scope: scope)
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { origin = $0 }
    }

    private var notch: BarNotch? {
        guard let key = element.scope.screenKey, case .record(let screen) = scope.context.runtime?.screen(key) ?? .null,
              case .record(let left)? = screen["notch-left"], case .record(let right)? = screen["notch-right"],
              let leftX = StyleValues.numberValue(left["x"] ?? .null), let leftWidth = StyleValues.numberValue(left["width"] ?? .null),
              let rightX = StyleValues.numberValue(right["x"] ?? .null)
        else { return nil }
        return BarNotch(leftEnd: CGFloat(leftX + leftWidth) - origin, rightStart: CGFloat(rightX) - origin)
    }
}
