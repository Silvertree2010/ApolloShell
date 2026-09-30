import SwiftUI
import ApolloConfig
import ApolloStyle
import ApolloRuntime

@MainActor
enum DisplayRenderers {
    static func ring(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        let value = clamp(StyleValues.numberValue(element.property("value")) ?? 0)
        let gap = clamp(StyleValues.numberValue(element.property("gap")) ?? 0)
        let sweep = angle(style["-apollo-sweep-angle"]) ?? 360
        let start = angle(style["-apollo-start-angle"]) ?? -90
        return AnyView(RingView(value: value, gap: gap, start: start, sweep: sweep, style: DisplayStyle(style))
            .animation(StyleMotion.valueAnimation(style), value: value))
    }

    static func gauge(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        let value = clamp(StyleValues.numberValue(element.property("value")) ?? 0)
        let ticks = max(0, StyleValues.count(element.property("ticks"), limit: 1000) ?? 0)
        return AnyView(GaugeView(value: value, ticks: ticks, style: DisplayStyle(style))
            .animation(StyleMotion.valueAnimation(style), value: value))
    }

    static func graph(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        var values: [Double] = []
        if case .list(let list) = element.property("values") { values = list.compactMap(StyleValues.numberValue) }
        var slots: Int?
        if let capacity = StyleValues.numberValue(element.property("capacity")), capacity >= 0 {
            let capacity = Int(min(capacity, 100_000))
            slots = capacity
            if values.count > capacity { values = Array(values.suffix(capacity)) }
        }
        let scale = GraphScale(values: values, min: StyleValues.numberValue(element.property("min")), max: StyleValues.numberValue(element.property("max")))
        let kind = element.property("kind").plainText ?? "line"
        var fill: [BackgroundLayer] = []
        if case .layers(let list)? = style["-apollo-fill"] { fill = list }
        return AnyView(GraphView(values: values, slots: slots, scale: scale, kind: kind, fill: fill, style: DisplayStyle(style), context: scope.context)
            .animation(StyleMotion.valueAnimation(style), value: scale))
    }

    static func progress(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        let raw = element.property("value")
        let value = raw == .null ? nil : clamp(StyleValues.numberValue(raw) ?? 0)
        let vertical = element.property("vertical").isTruthy
        var fill: [BackgroundLayer] = [.color(.system(name: "-apple-system-control-accent", alpha: 1))]
        if case .layers(let list)? = style["-apollo-fill-color"] { fill = list }
        let shape = style["border-radius"] != nil ? AnyShape(StyleShape(style)) : AnyShape(Capsule())
        return AnyView(ProgressBar(value: value, vertical: vertical, fill: fill, track: DisplayStyle(style).track, shape: shape, squared: style["border-radius"] != nil, context: scope.context)
            .animation(StyleMotion.valueAnimation(style), value: value))
    }

    static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }

    static func angle(_ value: CSSValue?) -> Double? {
        if case .angle(let degrees)? = value { return degrees }
        return nil
    }
}

struct DisplayStyle {
    var stroke: Color
    var track: Color
    var width: CGFloat

    init(_ style: ComputedStyle) {
        if case .color(let color)? = style["color"] { stroke = StyleValues.color(color) } else { stroke = .accentColor }
        if case .color(let color)? = style["-apollo-track-color"] { track = StyleValues.color(color) } else { track = Color.primary.opacity(0.12) }
        width = StyleValues.points(style["-apollo-stroke-width"]) ?? 4
    }
}

struct ArcShape: Shape {
    var start: Double
    var end: Double
    var inset: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(start, end) }
        set { start = newValue.first; end = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard end > start else { return path }
        let radius = max(0, min(rect.width, rect.height) / 2 - inset)
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        return path
    }
}

struct RingView: View {
    var value: Double
    var gap: Double
    var start: Double
    var sweep: Double
    var style: DisplayStyle

    var body: some View {
        let stroke = StrokeStyle(lineWidth: style.width, lineCap: .round)
        let filled = start + sweep * value
        let spacing = sweep * gap
        let trackStart = gap > 0 ? filled + spacing : start
        let trackEnd = gap > 0 ? start + sweep - (value > 0 && sweep >= 360 ? spacing : 0) : start + sweep
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    ArcShape(start: trackStart, end: trackEnd, inset: style.width / 2).stroke(style.track, style: stroke)
                    if value > 0 {
                        ArcShape(start: start, end: filled, inset: style.width / 2).stroke(style.stroke, style: stroke)
                    }
                }
            }
        .accessibilityValue(Text("\(Int((value * 100).rounded())) %"))
    }
}

struct GaugeView: View {
    var value: Double
    var ticks: Int
    var style: DisplayStyle

    static let start = 135.0
    static let sweep = 270.0

    var body: some View {
        let stroke = StrokeStyle(lineWidth: style.width, lineCap: .round)
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    ArcShape(start: Self.start, end: Self.start + Self.sweep, inset: style.width / 2).stroke(style.track, style: stroke)
                    if value > 0 {
                        ArcShape(start: Self.start, end: Self.start + Self.sweep * value, inset: style.width / 2).stroke(style.stroke, style: stroke)
                    }
                    if ticks > 1 {
                        GaugeTicks(count: ticks, inset: style.width * 1.5).stroke(style.track, lineWidth: 1)
                    }
                }
            }
        .accessibilityValue(Text("\(Int((value * 100).rounded())) %"))
    }
}

struct GaugeTicks: Shape {
    var count: Int
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2 - inset
        let inner = outer - max(2, outer * 0.12)
        for index in 0..<count {
            let degrees = GaugeView.start + GaugeView.sweep * Double(index) / Double(count - 1)
            let radians = degrees * .pi / 180
            path.move(to: CGPoint(x: center.x + inner * cos(radians), y: center.y + inner * sin(radians)))
            path.addLine(to: CGPoint(x: center.x + outer * cos(radians), y: center.y + outer * sin(radians)))
        }
        return path
    }
}

struct GraphScale: Equatable {
    var low: Double
    var high: Double

    init(values: [Double], min: Double?, max: Double?) {
        low = min ?? 0
        let top = max ?? values.max() ?? 1
        high = top > low ? top : low + 1
    }

    func fraction(_ value: Double) -> Double {
        Swift.min(1, Swift.max(0, (value - low) / (high - low)))
    }
}

struct GraphLine: Shape {
    var points: [Double]
    var slots: Int? = nil
    var closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !points.isEmpty else { return path }
        if slots != nil, points.count < 2 { return path }
        let count = max(slots ?? points.count, points.count)
        let offset = count - points.count
        let step = count > 1 ? rect.width / CGFloat(count - 1) : 0
        func point(_ index: Int) -> CGPoint {
            CGPoint(x: rect.minX + CGFloat(offset + index) * step, y: rect.maxY - CGFloat(points[index]) * rect.height)
        }
        if closed { path.move(to: CGPoint(x: point(0).x, y: rect.maxY)); path.addLine(to: point(0)) } else { path.move(to: point(0)) }
        for index in points.indices.dropFirst() {
            let previous = point(index - 1)
            let here = point(index)
            path.addQuadCurve(to: CGPoint(x: (previous.x + here.x) / 2, y: (previous.y + here.y) / 2), control: previous)
        }
        path.addLine(to: point(points.count - 1))
        if closed {
            path.addLine(to: CGPoint(x: point(points.count - 1).x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

struct GraphBars: Shape {
    var points: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !points.isEmpty else { return path }
        let slot = rect.width / CGFloat(points.count)
        let width = max(1, slot * 0.7)
        for (index, value) in points.enumerated() {
            let height = CGFloat(value) * rect.height
            path.addRect(CGRect(x: rect.minX + CGFloat(index) * slot + (slot - width) / 2, y: rect.maxY - height, width: width, height: height))
        }
        return path
    }
}

struct GraphView: View {
    var values: [Double]
    var slots: Int?
    var scale: GraphScale
    var kind: String
    var fill: [BackgroundLayer]
    var style: DisplayStyle
    var context: RenderContext

    var body: some View {
        let points = values.map(scale.fraction)
        ZStack {
            switch kind {
            case "bars":
                GraphBars(points: points).fill(style.stroke)
            case "area":
                BackgroundLayers(style: ComputedStyle(values: ["background": .layers(fill.isEmpty ? [.color(.system(name: "-apple-system-control-accent", alpha: 0.3))] : fill)]),
                                 shape: AnyShape(GraphLine(points: points, slots: slots, closed: true)), context: context)
                GraphLine(points: points, slots: slots, closed: false).stroke(style.stroke, style: StrokeStyle(lineWidth: style.width, lineCap: .round, lineJoin: .round))
            default:
                GraphLine(points: points, slots: slots, closed: false).stroke(style.stroke, style: StrokeStyle(lineWidth: style.width, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(minWidth: 10, minHeight: 10)
    }
}

struct ProgressBar: View {
    var value: Double?
    var vertical: Bool
    var fill: [BackgroundLayer]
    var track: Color
    var shape: AnyShape = AnyShape(Capsule())
    var squared = false
    var context: RenderContext
    @Environment(\.renderMode) private var renderMode
    @Environment(\.surfaceShown) private var shown

    var body: some View {
        GeometryReader { proxy in
            let length = vertical ? proxy.size.height : proxy.size.width
            ZStack(alignment: vertical ? .bottom : .leading) {
                shape.fill(track)
                if let value {
                    paint.frame(width: vertical ? nil : length * value, height: vertical ? length * value : nil)
                } else {
                    TimelineView(.animation(paused: renderMode || !shown)) { timeline in
                        let phase = renderMode ? 0.25 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
                        paint.frame(width: vertical ? nil : length * 0.3, height: vertical ? length * 0.3 : nil)
                            .offset(x: vertical ? 0 : (length * 1.3) * phase - length * 0.3, y: vertical ? -((length * 1.3) * phase - length * 0.3) : 0)
                    }
                }
            }
            .clipShape(shape)
        }
        .frame(minWidth: vertical ? 4 : 20, minHeight: vertical ? 20 : 4)
        .accessibilityValue(Text(value.map { "\(Int(($0 * 100).rounded())) %" } ?? ""))
    }

    var paint: some View {
        BackgroundLayers(style: ComputedStyle(values: ["background": .layers(fill)]), shape: squared ? AnyShape(Rectangle()) : AnyShape(Capsule()), context: context)
    }
}
