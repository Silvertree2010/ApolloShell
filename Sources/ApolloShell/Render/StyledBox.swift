import SwiftUI
import AppKit
import ApolloStyle

struct BoxParts: Equatable {
    var padding = true, margin = true, size = true, aspect = true, paint = true, shadow = true, border = true, clip = true
    var opacity = true, transform = true, depth = true, pointer = true, cursor = true, motion = true

    static let all = BoxParts()

    @MainActor
    init(styles: StyleResolver, subject: StaticSubject) {
        func has(_ names: String...) -> Bool { styles.engine.mayDeclare(anyOf: names, subject) }
        padding = has("padding")
        margin = has("margin")
        size = has("width", "height", "min-width", "min-height", "max-width", "max-height")
        aspect = has("aspect-ratio")
        paint = has("background")
        shadow = has("box-shadow")
        border = has("border")
        clip = has("overflow")
        opacity = has("opacity")
        transform = has("transform")
        depth = has("z-index")
        pointer = styles.engine.mayDeclare(anyOf: ["pointer-events"], subject, includingNone: true)
        cursor = styles.engine.mayDeclare(anyOf: ["cursor"], subject, includingNone: true)
        motion = has("transition", "animation", "-apollo-appear", "-apollo-disappear")
    }

    init() {}

    init(names: [String]) {
        func has(_ keys: String...) -> Bool { names.contains { n in keys.contains { n == $0 || n.hasPrefix($0 + "-") } } }
        padding = has("padding")
        margin = has("margin")
        size = has("width", "height", "min-width", "min-height", "max-width", "max-height")
        aspect = has("aspect-ratio")
        paint = has("background")
        shadow = has("box-shadow")
        border = has("border")
        clip = has("overflow")
        opacity = has("opacity")
        transform = has("transform")
        depth = has("z-index")
        pointer = has("pointer-events")
        cursor = has("cursor")
        motion = has("transition", "animation", "-apollo-appear", "-apollo-disappear")
    }

    func merged(_ o: BoxParts) -> BoxParts {
        var r = self
        r.padding = padding || o.padding
        r.margin = margin || o.margin
        r.size = size || o.size
        r.aspect = aspect || o.aspect
        r.paint = paint || o.paint
        r.shadow = shadow || o.shadow
        r.border = border || o.border
        r.clip = clip || o.clip
        r.opacity = opacity || o.opacity
        r.transform = transform || o.transform
        r.depth = depth || o.depth
        r.pointer = pointer || o.pointer
        r.cursor = cursor || o.cursor
        r.motion = motion || o.motion
        return r
    }
}

struct InlineUse {
    var parts: BoxParts
    var filter: Bool
    var animation: Bool
}

struct InheritedParts: Equatable {
    var pointer = true
    var cursor = true
}

extension View {
    @ViewBuilder
    func gated<R: View>(_ on: Bool, _ apply: (Self) -> R) -> some View {
        if on { apply(self) } else { self }
    }
}

struct StyledBox: ViewModifier {
    let style: ComputedStyle
    let context: RenderContext
    var padded = true
    var fill = Definite()
    var form: AnyShape?
    var flyouts: AnyView?
    var anchorID: String?
    var dynamicInline = false
    var alignment: Alignment = .center
    var parts = BoxParts.all
    var outer = true

    func body(content: Content) -> some View {
        let shape = form ?? AnyShape(StyleShape(style))
        let glass = parts.paint || form != nil ? BackgroundLayers.hostedGlass(style) : nil
        content
            .boxLayout(style: style, padded: padded, fill: fill, alignment: alignment, parts: parts)
            .boxPaint(style: style, context: context, parts: parts, shape: shape, forced: form != nil, hosted: glass != nil)
            .modifier(BoxEffects(style: style, parts: parts, flyouts: flyouts, anchorID: anchorID, dynamicInline: dynamicInline, outer: outer,
                                 glass: glass.map { GlassHost(glass: $0, shape: shape) }))
    }
}

struct BoxEffects: ViewModifier {
    let style: ComputedStyle
    let parts: BoxParts
    let flyouts: AnyView?
    let anchorID: String?
    let dynamicInline: Bool
    var outer = true
    var glass: GlassHost?

    func body(content: Content) -> some View {
        content.boxEffects(style: style, parts: parts, flyouts: flyouts, anchorID: anchorID, dynamicInline: dynamicInline, outer: outer, glass: glass)
    }
}

struct BoxOuter: ViewModifier {
    let style: ComputedStyle
    let parts: BoxParts

    func body(content: Content) -> some View {
        content
            .gated(parts.transform) { $0.modifier(Transform(style["transform"])) }
            .gated(parts.margin) { $0.padding(StyleValues.sides(style["margin"])) }
    }
}

extension View {
    func boxLayout(style: ComputedStyle, padded: Bool, fill: Definite, alignment: Alignment, parts: BoxParts) -> some View {
        let width = style["width"], height = style["height"]
        let fillsWidth = fill.width || StyleValues.percent(width) != nil, fillsHeight = fill.height || StyleValues.percent(height) != nil
        return self
            .gated(parts.padding && padded) { $0.padding(StyleValues.sides(style["padding"])) }
            .gated(parts.size || fill.width || fill.height) {
                $0.frame(width: StyleValues.size(width), height: StyleValues.size(height), alignment: alignment)
                    .frame(minWidth: StyleValues.size(style["min-width"]), maxWidth: fillsWidth ? .infinity : StyleValues.limit(style["max-width"]),
                           minHeight: StyleValues.size(style["min-height"]), maxHeight: fillsHeight ? .infinity : StyleValues.limit(style["max-height"]), alignment: alignment)
            }
            .gated(parts.aspect) { $0.modifier(AspectRatio(ratio: StyleValues.number(style["aspect-ratio"]))) }
    }

    func boxPaint(style: ComputedStyle, context: RenderContext, parts: BoxParts, shape: AnyShape, forced: Bool, hosted: Bool = false) -> some View {
        self
            .gated(parts.paint || forced) { $0.background { BackgroundLayers(style: style, shape: shape, context: context, hosted: hosted) } }
            .gated(parts.border) { $0.overlay { BorderLayer(style: style, shape: shape) } }
            .gated(parts.clip) { $0.modifier(Clip(active: StyleValues.keyword(style["overflow"]) == "hidden", shape: shape)) }
            .gated(parts.shadow) { $0.modifier(BoxShadows(style["box-shadow"], shape: shape)) }
    }

    func boxEffects(style: ComputedStyle, parts: BoxParts, flyouts: AnyView?, anchorID: String?, dynamicInline: Bool, outer: Bool = true, glass: GlassHost? = nil) -> some View {
        self
            .gated(flyouts != nil) { $0.modifier(FlyoutOverlay(layer: flyouts)) }
            .gated(glass != nil) { $0.modifier(glass ?? GlassHost(glass: nil, shape: AnyShape(Rectangle()))) }
            .gated(dynamicInline) { $0.modifier(Filters(style["filter"], enabled: dynamicInline)) }
            .gated(parts.opacity) { $0.opacity(StyleValues.number(style["opacity"]) ?? 1) }
            .gated(parts.transform && outer) { $0.modifier(Transform(style["transform"])) }
            .gated(anchorID != nil) { $0.modifier(AnchorReport(id: anchorID)) }
            .gated(parts.margin && outer) { $0.padding(StyleValues.sides(style["margin"])) }
            .gated(parts.depth) { $0.zIndex(StyleValues.number(style["z-index"]) ?? 0) }
            .gated(parts.pointer) { $0.allowsHitTesting(StyleValues.keyword(style["pointer-events"]) != "none") }
            .gated(parts.cursor) { $0.modifier(Cursor(name: StyleValues.keyword(style["cursor"]))) }
    }
}

struct StyleShape: InsettableShape {
    var radius: CGFloat
    var percentRadius: CGFloat?
    var circular: Bool
    var inset: CGFloat = 0

    init(_ style: ComputedStyle) {
        circular = StyleValues.keyword(style["-apollo-corner-shape"]) == "circular"
        if case .lengths(let list)? = style["border-radius"], let first = list.first, first.unit == .percent {
            percentRadius = first.value / 100
            radius = 0
        } else {
            percentRadius = nil
            radius = StyleValues.radius(style["border-radius"])
        }
    }

    func inset(by amount: CGFloat) -> StyleShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        let limit = min(rect.width, rect.height) / 2
        let value = max(0, min(limit, (percentRadius.map { $0 * min(rect.width + 2 * inset, rect.height + 2 * inset) } ?? radius) - inset))
        return RoundedRectangle(cornerRadius: value, style: circular ? .circular : .continuous).path(in: rect)
    }
}

struct AspectRatio: ViewModifier {
    let ratio: Double?

    func body(content: Content) -> some View {
        AspectLayout(ratio: ratio.flatMap { $0 > 0 ? CGFloat($0) : nil }) { content }
    }
}

struct AspectLayout: GuideFreeLayout {
    let ratio: CGFloat?

    func target(_ proposal: ProposedViewSize, _ subview: LayoutSubview) -> ProposedViewSize {
        guard let ratio else { return proposal }
        switch (proposal.width, proposal.height) {
        case let (width?, height?):
            let fitted = min(width, height * ratio)
            return ProposedViewSize(width: fitted, height: fitted / ratio)
        case let (width?, nil):
            return ProposedViewSize(width: width, height: width / ratio)
        case let (nil, height?):
            return ProposedViewSize(width: height * ratio, height: height)
        case (nil, nil):
            let ideal = subview.sizeThatFits(.unspecified)
            let width = ideal.height > 0 ? min(ideal.width, ideal.height * ratio) : ideal.width
            return ProposedViewSize(width: width, height: width / ratio)
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        LayoutCounter.measured()
        guard let subview = subviews.first else { return .zero }
        return subview.sizeThatFits(target(proposal, subview))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        LayoutCounter.placed()
        guard let subview = subviews.first else { return }
        subview.place(at: bounds.origin, proposal: target(proposal, subview))
    }
}

struct Clip: ViewModifier {
    let active: Bool
    let shape: AnyShape

    func body(content: Content) -> some View {
        content.clipShape(ClipForm(active: active, shape: shape)).modifier(HitRegionClip(active: active))
    }
}

struct ClipForm: Shape {
    let active: Bool
    let shape: AnyShape

    func path(in rect: CGRect) -> Path {
        active ? shape.path(in: rect) : Path(rect.insetBy(dx: -100_000, dy: -100_000))
    }
}

struct Filters: ViewModifier {
    static let slots = 4
    let operations: [FilterOperation]
    let enabled: Bool

    init(_ value: CSSValue?, enabled: Bool) {
        if case .filters(let list)? = value { operations = list } else { operations = [] }
        self.enabled = enabled
    }

    func slot(_ index: Int) -> FilterOperation? {
        operations.indices.contains(index) ? operations[index] : nil
    }

    func body(content: Content) -> some View {
        if enabled {
            content
                .modifier(FilterSlot(operation: slot(0)))
                .gated(slot(1) != nil) { $0.modifier(FilterSlot(operation: slot(1))) }
                .gated(slot(2) != nil) { $0.modifier(FilterSlot(operation: slot(2))) }
                .gated(slot(3) != nil) { $0.modifier(FilterSlot(operation: slot(3))) }
        } else {
            content
        }
    }
}

struct FilterSlot: ViewModifier {
    let operation: FilterOperation?

    func body(content: Content) -> some View {
        var blur: CGFloat = 0
        var shadow: Shadow?
        switch operation {
        case .blur(let radius)?: blur = radius
        case .dropShadow(let value)?: shadow = value
        case nil: break
        }
        return content
            .blur(radius: blur)
            .shadow(color: shadow.map { StyleValues.color($0.color) } ?? .clear, radius: (shadow?.blur ?? 0) / 2, x: shadow?.x ?? 0, y: shadow?.y ?? 0)
    }
}

struct Transform: ViewModifier {
    let operations: [TransformOperation]

    init(_ value: CSSValue?) {
        if case .transform(let list)? = value { operations = list } else { operations = [] }
    }

    func body(content: Content) -> some View {
        var scale: CGFloat = 1, angle: Double = 0, offset = CGSize.zero
        for operation in operations {
            switch operation {
            case .scale(let factor): scale *= factor
            case .rotate(let degrees): angle += degrees
            case let .translate(x, y): offset.width += x; offset.height += y
            }
        }
        return content
            .scaleEffect(scale)
            .rotationEffect(.degrees(angle))
            .offset(offset)
    }
}

struct Cursor: ViewModifier {
    let name: String?

    func body(content: Content) -> some View {
        let style: PointerStyle? = switch name {
        case "pointer": .link
        case "text": .horizontalText
        case "grab": .grabIdle
        default: nil
        }
        return content.pointerStyle(style)
    }
}

struct BorderLayer: View {
    let style: ComputedStyle
    let shape: AnyShape

    var body: some View {
        if case let .border(width, dashed, color)? = style["border"], width > 0 {
            shape.stroke(StyleValues.color(color, current: foreground), style: StrokeStyle(lineWidth: width * 2, dash: dashed ? [width * 3, width * 2] : []))
                .clipShape(shape)
        }
    }

    var foreground: Color {
        if case .color(let color)? = style["color"] { return StyleValues.color(color) }
        return .primary
    }
}

struct GlassHost: ViewModifier {
    let glass: Glass?
    let shape: AnyShape
    @Environment(\.renderMode) private var renderMode

    func body(content: Content) -> some View {
        if let glass, !renderMode {
            content.glassEffect(glass, in: shape)
        } else {
            content
        }
    }
}

struct BackgroundLayers: View {
    let style: ComputedStyle
    let shape: AnyShape
    let context: RenderContext
    var hosted = false

    static func hostedGlass(_ style: ComputedStyle) -> Glass? {
        guard case .layers(let list)? = style["background"], case .glass(let variant, let tint)? = list.last, style["background-color"] == nil else { return nil }
        return StyleValues.glass(variant, tint: tint)
    }
    @Environment(\.renderMode) private var renderMode
    @Environment(\.colorScheme) private var colorScheme


    var glassClear: Bool {
        style.customProperties["--render-glass"]?.trimmingCharacters(in: .whitespaces).lowercased() == "clear"
    }

    var body: some View {
        ZStack {
            ForEach(Array((hosted && !renderMode && Self.hostedGlass(style) != nil ? Array(layers.dropLast()) : layers).reversed().enumerated()), id: \.offset) { _, layer in
                self.layer(layer)
            }
        }
    }

    var layers: [BackgroundLayer] {
        var result: [BackgroundLayer] = []
        if case .layers(let list)? = style["background"] { result = list }
        if case .color(let color)? = style["background-color"] { result.append(.color(color)) }
        return result
    }

    @ViewBuilder
    func layer(_ layer: BackgroundLayer) -> some View {
        switch layer {
        case .color(let color):
            shape.fill(StyleValues.color(color))
        case .gradient(let gradient):
            shape.fill(StyleValues.gradient(gradient))
        case .image(let path):
            if let image = context.styles.image(path) {
                Image(nsImage: image).resizable().scaledToFill().clipShape(shape)
            }
        case .glass(let variant, let tint):
            if renderMode {
                if glassClear {
                    Color.clear
                } else {
                    GlassStandIn(shape: shape, variant: variant, tint: tint, dark: colorScheme == .dark)
                }
            } else {
                Color.clear.glassEffect(StyleValues.glass(variant, tint: tint), in: shape)
            }
        case .material(let thickness):
            if renderMode {
                shape.fill(Color(nsColor: .windowBackgroundColor))
            } else {
                GeometryReader { proxy in
                    let rect = CGRect(origin: .zero, size: proxy.size)
                    let r = shape.path(in: rect).boundingRect.union(rect)
                    ZStack(alignment: .topLeading) {
                        VisualEffectMaterial(thickness: thickness)
                            .frame(width: rect.width, height: rect.height)
                            .mask { shape.fill(Color.black) }
                        if r != rect {
                            VisualEffectMaterial(thickness: thickness)
                                .frame(width: r.width, height: r.height)
                                .offset(x: r.minX, y: r.minY)
                                .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                                .transaction { $0.animation = nil }
                                .mask {
                                    Path { p in
                                        p.addPath(shape.path(in: rect))
                                        p.addRect(rect)
                                    }
                                    .fill(Color.black, style: FillStyle(eoFill: true))
                                }
                        }
                    }
                }
            }
        }
    }
}

struct GlassStandIn: View {
    let shape: AnyShape
    let variant: GlassVariant
    let tint: CSSColor?
    let dark: Bool

    var body: some View {
        let thin = variant == .clear
        ZStack {
            shape.fill(Color(white: dark ? 0.16 : 1).opacity(thin ? 0.22 : 0.62))
            if let tint {
                shape.fill(StyleValues.color(tint).opacity(min(1, Self.alpha(tint)) > 0.7 ? 0.7 / Self.alpha(tint) : 1))
            }
            shape.stroke(Color.white.opacity(dark ? 0.22 : 0.6), lineWidth: 2).clipShape(shape)
        }
    }

    static func alpha(_ c: CSSColor) -> Double {
        switch c {
        case let .rgba(_, _, _, a): a
        case let .system(_, a): a
        case .currentColor: 1
        }
    }
}

struct BoxShadows: ViewModifier {
    let shadows: [Shadow]
    let shape: AnyShape
    @Environment(\.renderMode) private var renderMode

    init(_ value: CSSValue?, shape: AnyShape) {
        if case .shadows(let list)? = value { shadows = list } else { shadows = [] }
        self.shape = shape
    }

    func body(content: Content) -> some View {
        content.background {
            if renderMode {
                ShadowCanvas(shadows: shadows, shape: shape)
            } else {
                live
            }
        }
    }

    var live: some View {
            ZStack {
                ForEach(Array(shadows.enumerated()), id: \.offset) { _, shadow in
                    shape
                        .fill(StyleValues.color(shadow.color))
                        .padding(-shadow.spread)
                        .offset(x: shadow.x, y: shadow.y)
                        .blur(radius: shadow.blur / 2)
                        .mask { ShadowMask(shape: shape) }
                }
            }
    }
}

struct ShadowCanvas: View {
    let shadows: [Shadow]
    let shape: AnyShape

    var body: some View {
        let e = shadows.map { CGFloat($0.blur + max(0, $0.spread) + max(abs($0.x), abs($0.y))) }.max() ?? 0
        Canvas { ctx, size in
            let r = CGRect(x: e, y: e, width: max(0, size.width - 2 * e), height: max(0, size.height - 2 * e))
            var out = Path(CGRect(origin: .zero, size: size))
            out.addPath(shape.path(in: r))
            ctx.clip(to: out, style: FillStyle(eoFill: true))
            for s in shadows {
                ctx.drawLayer { l in
                    if s.blur > 0 { l.addFilter(.blur(radius: CGFloat(s.blur) / 2)) }
                    let grown = r.insetBy(dx: -CGFloat(s.spread), dy: -CGFloat(s.spread)).offsetBy(dx: CGFloat(s.x), dy: CGFloat(s.y))
                    l.fill(shape.path(in: grown), with: .color(StyleValues.color(s.color)))
                }
            }
        }
        .padding(-e)
        .allowsHitTesting(false)
    }
}

struct ShadowMask: View {
    let shape: AnyShape

    var body: some View {
        Rectangle().padding(-1000).overlay { shape.blendMode(.destinationOut) }.compositingGroup()
    }
}

struct VisualEffectMaterial: NSViewRepresentable {
    let thickness: MaterialThickness

    static func material(_ t: MaterialThickness) -> NSVisualEffectView.Material {
        switch t {
        case .ultraThin, .thin: .fullScreenUI
        case .regular, .bar: .popover
        case .thick, .ultraThick: .menu
        }
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        v.material = Self.material(thickness)
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        let m = Self.material(thickness)
        if v.material != m { v.material = m }
    }
}
