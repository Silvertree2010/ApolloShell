import SwiftUI
import ApolloShellCore
import ApolloStyle

struct ChildMetrics: Equatable {
    var grow: CGFloat = 0
    var shrink: CGFloat = 0
    var shrinkDeclared = false
    var basis: CSSLength?
    var width: CGFloat?
    var height: CGFloat?
    var alignSelf: String?
    var justifySelf: String?
    var marginH: CGFloat = 0
    var marginV: CGFloat = 0
    var span = 1
    var rowSpan = 1

    init() {}

    init(_ style: ComputedStyle, spacer: Bool = false) {
        grow = CGFloat(StyleValues.number(style["flex-grow"]) ?? (spacer ? 1 : 0))
        let declaredShrink = StyleValues.number(style["flex-shrink"])
        shrink = CGFloat(declaredShrink ?? 0)
        shrinkDeclared = declaredShrink != nil
        if let length = StyleValues.length(style["flex-basis"]), length.unit != .auto { basis = length }
        width = StyleValues.percent(style["width"])
        height = StyleValues.percent(style["height"])
        alignSelf = StyleValues.keyword(style["align-self"])
        justifySelf = StyleValues.keyword(style["justify-self"])
        if case .span(let count)? = style["grid-column"] { span = max(1, count) }
        if case .span(let count)? = style["grid-row"] { rowSpan = max(1, count) }
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
    var notch: BarNotch?

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

    private func basisMain(_ metrics: ChildMetrics, available: CGFloat?) -> CGFloat? {
        guard let basis = metrics.basis else { return nil }
        let margin = horizontal ? metrics.marginH : metrics.marginV
        let finite = available.map(\.isFinite) ?? false
        switch basis.unit {
        case .points where finite || metrics.grow == 0: return CGFloat(basis.value) + margin
        case .percent where finite: return (available ?? 0) * CGFloat(basis.value / 100) + margin
        default: return nil
        }
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

    private func crossFor(_ subview: LayoutSubview, _ metrics: ChildMetrics, main: CGFloat?, available: CGFloat?) -> CGFloat? {
        if let proposal = crossProposal(metrics, available: available) { return proposal }
        guard let available, available.isFinite else { return nil }
        let ideal = cross(subview.sizeThatFits(size(main: main, cross: nil)))
        return ideal > available ? available : nil
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
            if let basis = basisMain(metrics, available: available) { return basis }
            if let (fraction, margin) = percentMain(metrics), let available { return available * fraction + margin }
            return main(subview.sizeThatFits(size(main: nil, cross: crossFor(subview, metrics, main: nil, available: crossAvailable))))
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
            } else if over > 0, !metrics.contains(where: \.shrinkDeclared) {
                let crossAvailable = horizontal ? proposal.height : proposal.width
                let slack: [CGFloat] = subviews.indices.map { index in
                    guard metrics[index].grow == 0, metrics[index].basis == nil, percentMain(metrics[index]) == nil else { return 0 }
                    let smallest = main(subviews[index].sizeThatFits(size(main: 0, cross: crossFor(subviews[index], metrics[index], main: 0, available: crossAvailable))))
                    return max(0, sizes[index] - smallest)
                }
                let total = slack.reduce(0, +)
                if total > 0 {
                    let taken = min(over, total)
                    for index in sizes.indices where slack[index] > 0 {
                        sizes[index] -= taken * slack[index] / total
                    }
                }
            } else if over < 0, growth > 0 {
                for index in sizes.indices where metrics[index].grow > 0 {
                    sizes[index] = -over * metrics[index].grow / growth
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
            let measured = subview.sizeThatFits(size(main: sizes[index], cross: crossFor(subview, metrics, main: sizes[index], available: crossAvailable)))
            crossSize = max(crossSize, cross(measured))
        }
        var mainSize = sizes.reduce(0, +) + gap * CGFloat(subviews.count - 1)
        let available = horizontal ? proposal.width : proposal.height
        if let available, available.isFinite, justify != "start" || subviews.contains(where: { $0[ChildMetricsKey.self].grow > 0 })
            || (horizontal && ZoneRow.applies(subviews.map { $0[ChildMetricsKey.self] })) {
            mainSize = max(mainSize, available)
        }
        return definite.apply(horizontal ? CGSize(width: mainSize, height: crossSize) : CGSize(width: crossSize, height: mainSize), proposal)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        if horizontal, ZoneRow.applies(subviews.map { $0[ChildMetricsKey.self] }) {
            ZoneRow(gap: gap, align: align, notch: notch).place(in: bounds, subviews: subviews)
            return
        }
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
            let proposed = size(main: sizes[index], cross: crossFor(subview, metrics, main: sizes[index], available: crossLength))
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
            let countsWidth = metrics.width == nil || proposal.width != nil
            let countsHeight = metrics.height == nil || proposal.height != nil
            if !countsWidth && !countsHeight { continue }
            let measured = subview.sizeThatFits(childProposal(metrics, in: proposal))
            if countsWidth { result.width = max(result.width, measured.width) }
            if countsHeight { result.height = max(result.height, measured.height) }
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

struct GridLayout: Layout {
    var columns: [CSSLength]
    var columnGap: CGFloat
    var rowGap: CGFloat
    var rowHeight: CGFloat?
    var definite = Definite()

    struct Cell {
        var index: Int
        var row: Int
        var column: Int
        var span: Int
        var rowSpan = 1
    }

    func cells(_ subviews: Subviews) -> [Cell] {
        var result: [Cell] = []
        var occupied: Set<Int> = []
        var row = 0, column = 0
        let count = max(1, columns.count)
        for (index, subview) in subviews.enumerated() {
            let metrics = subview[ChildMetricsKey.self]
            let span = min(count, metrics.span)
            while true {
                if column + span > count { row += 1; column = 0; continue }
                if (column..<(column + span)).allSatisfy({ !occupied.contains(row * count + $0) }) { break }
                column += 1
            }
            result.append(Cell(index: index, row: row, column: column, span: span, rowSpan: metrics.rowSpan))
            for spanned in row..<(row + metrics.rowSpan) {
                for spannedColumn in column..<(column + span) { occupied.insert(spanned * count + spannedColumn) }
            }
            column += span
            if column >= count { row += 1; column = 0 }
        }
        return result
    }

    func rowSpanHeight(_ cell: Cell, _ heights: [CGFloat]) -> CGFloat {
        heights[cell.row..<min(heights.count, cell.row + cell.rowSpan)].reduce(0, +) + rowGap * CGFloat(cell.rowSpan - 1)
    }

    func widths(_ total: CGFloat?, subviews: Subviews) -> [CGFloat] {
        let gaps = columnGap * CGFloat(max(0, columns.count - 1))
        let fixed = columns.filter { $0.unit == .points }.map { CGFloat($0.value) }.reduce(0, +)
        let fractions = columns.filter { $0.unit == .fraction }.map { CGFloat($0.value) }.reduce(0, +)
        let free: CGFloat
        if let total, total.isFinite {
            free = max(0, total - gaps - fixed)
        } else {
            let widest = subviews.map { $0.sizeThatFits(.unspecified).width / CGFloat($0[ChildMetricsKey.self].span) }.max() ?? 0
            free = widest * fractions
        }
        return columns.map { $0.unit == .points ? CGFloat($0.value) : (fractions > 0 ? free * CGFloat($0.value) / fractions : 0) }
    }

    func spanWidth(_ cell: Cell, _ widths: [CGFloat]) -> CGFloat {
        widths[cell.column..<(cell.column + cell.span)].reduce(0, +) + columnGap * CGFloat(cell.span - 1)
    }

    func rows(_ cells: [Cell], _ widths: [CGFloat], _ subviews: Subviews) -> [CGFloat] {
        let count = cells.map { $0.row + $0.rowSpan }.max() ?? 0
        var heights = [CGFloat](repeating: rowHeight ?? 0, count: count)
        guard rowHeight == nil else { return heights }
        for cell in cells where cell.rowSpan == 1 {
            let size = subviews[cell.index].sizeThatFits(ProposedViewSize(width: spanWidth(cell, widths), height: nil))
            heights[cell.row] = max(heights[cell.row], size.height)
        }
        for cell in cells where cell.rowSpan > 1 {
            let size = subviews[cell.index].sizeThatFits(ProposedViewSize(width: spanWidth(cell, widths), height: nil))
            let missing = size.height - rowSpanHeight(cell, heights)
            if missing > 0 { heights[cell.row + cell.rowSpan - 1] += missing }
        }
        return heights
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widths = widths(proposal.width, subviews: subviews)
        let heights = rows(cells(subviews), widths, subviews)
        let width = widths.reduce(0, +) + columnGap * CGFloat(max(0, widths.count - 1))
        let height = heights.reduce(0, +) + rowGap * CGFloat(max(0, heights.count - 1))
        return definite.apply(CGSize(width: width, height: height), proposal)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = widths(bounds.width, subviews: subviews)
        let cells = cells(subviews)
        let heights = rows(cells, widths, subviews)
        for cell in cells {
            let x = bounds.minX + widths[0..<cell.column].reduce(0, +) + columnGap * CGFloat(cell.column)
            let y = bounds.minY + heights[0..<cell.row].reduce(0, +) + rowGap * CGFloat(cell.row)
            subviews[cell.index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                       proposal: ProposedViewSize(width: spanWidth(cell, widths), height: rowSpanHeight(cell, heights)))
        }
    }
}
