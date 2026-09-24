import SwiftUI
import ApolloStyle

struct ChildMetrics: Equatable {
    var grow: CGFloat = 0
    var shrink: CGFloat = 0
    var width: CGFloat?
    var height: CGFloat?
    var alignSelf: String?
    var justifySelf: String?
    var marginH: CGFloat = 0
    var marginV: CGFloat = 0

    init() {}

    init(_ style: ComputedStyle) {
        grow = CGFloat(StyleValues.number(style["flex-grow"]) ?? 0)
        shrink = CGFloat(StyleValues.number(style["flex-shrink"]) ?? 0)
        width = StyleValues.percent(style["width"])
        height = StyleValues.percent(style["height"])
        alignSelf = StyleValues.keyword(style["align-self"])
        justifySelf = StyleValues.keyword(style["justify-self"])
        let margin = StyleValues.sides(style["margin"])
        marginH = margin.leading + margin.trailing
        marginV = margin.top + margin.bottom
    }
}

struct ChildMetricsKey: LayoutValueKey {
    static let defaultValue = ChildMetrics()
}

struct Definite: Equatable {
    var width = false
    var height = false

    init(width: Bool = false, height: Bool = false) {
        self.width = width
        self.height = height
    }

    init(_ style: ComputedStyle) {
        width = StyleValues.points(style["width"]) != nil || StyleValues.percent(style["width"]) != nil
        height = StyleValues.points(style["height"]) != nil || StyleValues.percent(style["height"]) != nil
    }

    func apply(_ size: CGSize, _ proposal: ProposedViewSize) -> CGSize {
        var result = size
        if width, let proposed = proposal.width, proposed.isFinite { result.width = proposed }
        if height, let proposed = proposal.height, proposed.isFinite { result.height = proposed }
        return result
    }
}

struct FlexLayout: Layout {
    var horizontal: Bool
    var gap: CGFloat
    var align: String
    var justify: String
    var definite = Definite()

    private func main(_ size: CGSize) -> CGFloat { horizontal ? size.width : size.height }
    private func cross(_ size: CGSize) -> CGFloat { horizontal ? size.height : size.width }
    private func size(main: CGFloat?, cross: CGFloat?) -> ProposedViewSize {
        horizontal ? ProposedViewSize(width: main, height: cross) : ProposedViewSize(width: cross, height: main)
    }

    private func percentMain(_ metrics: ChildMetrics) -> (CGFloat, CGFloat)? {
        if horizontal, let width = metrics.width { return (width, metrics.marginH) }
        if !horizontal, let height = metrics.height { return (height, metrics.marginV) }
        return nil
    }

    private func percentCross(_ metrics: ChildMetrics) -> (CGFloat, CGFloat)? {
        if horizontal, let height = metrics.height { return (height, metrics.marginV) }
        if !horizontal, let width = metrics.width { return (width, metrics.marginH) }
        return nil
    }

    private func alignment(_ metrics: ChildMetrics) -> String {
        guard let own = metrics.alignSelf, own != "auto" else { return align }
        return own
    }

    private func crossProposal(_ metrics: ChildMetrics, available: CGFloat?) -> CGFloat? {
        if let (fraction, margin) = percentCross(metrics), let available { return available * fraction + margin }
        if alignment(metrics) == "stretch" { return available }
        return nil
    }

    private func mains(_ subviews: Subviews, proposal: ProposedViewSize) -> [CGFloat] {
        let available = horizontal ? proposal.width : proposal.height
        let crossAvailable = horizontal ? proposal.height : proposal.width
        var sizes: [CGFloat] = subviews.map { subview in
            let metrics = subview[ChildMetricsKey.self]
            if let (fraction, margin) = percentMain(metrics), let available { return available * fraction + margin }
            return main(subview.sizeThatFits(size(main: nil, cross: crossProposal(metrics, available: crossAvailable))))
        }
        guard let available, available.isFinite else { return sizes }
        let used = sizes.reduce(0, +) + gap * CGFloat(max(0, subviews.count - 1))
        let metrics = subviews.map { $0[ChildMetricsKey.self] }
        let growth = metrics.map(\.grow).reduce(0, +)
        if used < available, growth > 0 {
            let free = available - used
            for index in sizes.indices where metrics[index].grow > 0 {
                sizes[index] += free * metrics[index].grow / growth
            }
        } else if used > available {
            for index in sizes.indices where metrics[index].grow > 0 { sizes[index] = 0 }
            let over = sizes.reduce(0, +) + gap * CGFloat(max(0, subviews.count - 1)) - available
            let shrinking = metrics.indices.filter { metrics[$0].shrink > 0 }.map { metrics[$0].shrink * sizes[$0] }.reduce(0, +)
            if over > 0, shrinking > 0 {
                for index in sizes.indices where metrics[index].shrink > 0 {
                    sizes[index] = max(0, sizes[index] - over * metrics[index].shrink * sizes[index] / shrinking)
                }
            }
        }
        return sizes
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let sizes = mains(subviews, proposal: proposal)
        let crossAvailable = horizontal ? proposal.height : proposal.width
        var crossSize: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let metrics = subview[ChildMetricsKey.self]
            let measured = subview.sizeThatFits(size(main: sizes[index], cross: crossProposal(metrics, available: crossAvailable)))
            crossSize = max(crossSize, cross(measured))
        }
        var mainSize = sizes.reduce(0, +) + gap * CGFloat(subviews.count - 1)
        let available = horizontal ? proposal.width : proposal.height
        if let available, available.isFinite, justify != "start" || subviews.contains(where: { $0[ChildMetricsKey.self].grow > 0 }) {
            mainSize = max(mainSize, available)
        }
        return definite.apply(horizontal ? CGSize(width: mainSize, height: crossSize) : CGSize(width: crossSize, height: mainSize), proposal)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let sizes = mains(subviews, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        let total = sizes.reduce(0, +) + gap * CGFloat(subviews.count - 1)
        let free = max(0, main(bounds.size) - total)
        var spacing = gap
        var position: CGFloat = 0
        let count = CGFloat(subviews.count)
        switch justify {
        case "center": position = free / 2
        case "end": position = free
        case "space-between": spacing += count > 1 ? free / (count - 1) : 0
        case "space-around": spacing += free / count; position = free / count / 2
        case "space-evenly": spacing += free / (count + 1); position = free / (count + 1)
        default: break
        }
        let crossLength = cross(bounds.size)
        for (index, subview) in subviews.enumerated() {
            let metrics = subview[ChildMetricsKey.self]
            let proposed = size(main: sizes[index], cross: crossProposal(metrics, available: crossLength))
            let measured = subview.sizeThatFits(proposed)
            let offset: CGFloat
            switch alignment(metrics) {
            case "start", "stretch": offset = 0
            case "end": offset = crossLength - cross(measured)
            default: offset = (crossLength - cross(measured)) / 2
            }
            let mainOffset = position + (sizes[index] - main(measured)) / 2
            let point = horizontal
                ? CGPoint(x: bounds.minX + mainOffset, y: bounds.minY + offset)
                : CGPoint(x: bounds.minX + offset, y: bounds.minY + mainOffset)
            subview.place(at: point, anchor: .topLeading, proposal: horizontal
                ? ProposedViewSize(width: sizes[index], height: measured.height)
                : ProposedViewSize(width: measured.width, height: sizes[index]))
            position += sizes[index] + spacing
        }
    }
}

struct StackLayout: Layout {
    var definite = Definite()

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var result = CGSize.zero
        for subview in subviews {
            let metrics = subview[ChildMetricsKey.self]
            if metrics.width != nil && metrics.height != nil { continue }
            let measured = subview.sizeThatFits(childProposal(metrics, in: proposal))
            result.width = max(result.width, metrics.width == nil ? measured.width : 0)
            result.height = max(result.height, metrics.height == nil ? measured.height : 0)
        }
        return definite.apply(result, proposal)
    }

    private func childProposal(_ metrics: ChildMetrics, in proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(
            width: metrics.width.flatMap { fraction in proposal.width.map { $0 * fraction + metrics.marginH } } ?? proposal.width,
            height: metrics.height.flatMap { fraction in proposal.height.map { $0 * fraction + metrics.marginV } } ?? proposal.height
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let metrics = subview[ChildMetricsKey.self]
            let childProposal = childProposal(metrics, in: ProposedViewSize(bounds.size))
            let measured = subview.sizeThatFits(childProposal)
            let x: CGFloat
            switch metrics.alignSelf {
            case "start": x = bounds.minX
            case "end": x = bounds.maxX - measured.width
            default: x = bounds.midX - measured.width / 2
            }
            let y: CGFloat
            switch metrics.justifySelf {
            case "start": y = bounds.minY
            case "end": y = bounds.maxY - measured.height
            default: y = bounds.midY - measured.height / 2
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(measured))
        }
    }
}
