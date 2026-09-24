import SwiftUI
import AppKit
import ApolloStyle

struct StyledBox: ViewModifier {
    let style: ComputedStyle
    let context: RenderContext
    var padded = true
    var fill = Definite()
    var form: AnyShape?

    func body(content: Content) -> some View {
        let width = style["width"], height = style["height"]
        let shape = form ?? AnyShape(StyleShape(style))
        let fillsWidth = fill.width || StyleValues.percent(width) != nil, fillsHeight = fill.height || StyleValues.percent(height) != nil
        content
            .padding(padded ? StyleValues.sides(style["padding"]) : EdgeInsets())
            .frame(width: StyleValues.points(width), height: StyleValues.points(height))
            .frame(minWidth: StyleValues.points(style["min-width"]), maxWidth: fillsWidth ? .infinity : StyleValues.points(style["max-width"]),
                   minHeight: StyleValues.points(style["min-height"]), maxHeight: fillsHeight ? .infinity : StyleValues.points(style["max-height"]))
            .modifier(AspectRatio(ratio: StyleValues.number(style["aspect-ratio"])))
            .background { BackgroundLayers(style: style, shape: shape, context: context) }
            .overlay { BorderLayer(style: style, shape: shape) }
            .modifier(Clip(active: StyleValues.keyword(style["overflow"]) == "hidden", shape: shape))
            .modifier(Filters(style["filter"]))
            .opacity(StyleValues.number(style["opacity"]) ?? 1)
            .modifier(Transform(style["transform"]))
            .padding(StyleValues.sides(style["margin"]))
            .zIndex(StyleValues.number(style["z-index"]) ?? 0)
            .allowsHitTesting(StyleValues.keyword(style["pointer-events"]) != "none")
            .modifier(Cursor(name: StyleValues.keyword(style["cursor"])))
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
        if let ratio, ratio > 0 {
            content.aspectRatio(ratio, contentMode: .fit)
        } else {
            content
        }
    }
}

struct Clip: ViewModifier {
    let active: Bool
    let shape: AnyShape

    func body(content: Content) -> some View {
        if active { content.clipShape(shape) } else { content }
    }
}

struct Filters: ViewModifier {
    let operations: [FilterOperation]

    init(_ value: CSSValue?) {
        if case .filters(let list)? = value { operations = list } else { operations = [] }
    }

    func body(content: Content) -> some View {
        operations.reduce(AnyView(content)) { view, operation in
            switch operation {
            case .blur(let radius):
                AnyView(view.blur(radius: radius))
            case .dropShadow(let shadow):
                AnyView(view.shadow(color: StyleValues.color(shadow.color), radius: shadow.blur / 2, x: shadow.x, y: shadow.y))
            }
        }
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
        switch name {
        case "pointer": content.pointerStyle(.link)
        case "text": content.pointerStyle(.horizontalText)
        case "grab": content.pointerStyle(.grabIdle)
        default: content
        }
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

struct BackgroundLayers: View {
    let style: ComputedStyle
    let shape: AnyShape
    let context: RenderContext
    @Environment(\.renderMode) private var renderMode

    var body: some View {
        ZStack {
            ForEach(Array(layers.reversed().enumerated()), id: \.offset) { _, layer in
                self.layer(layer)
            }
        }
        .modifier(BoxShadows(style["box-shadow"], shape: shape))
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
                Color.clear
            } else {
                Color.clear.glassEffect(StyleValues.glass(variant, tint: tint), in: shape)
            }
        case .material(let thickness):
            if renderMode {
                shape.fill(Color(nsColor: .windowBackgroundColor))
            } else {
                shape.fill(StyleValues.material(thickness))
            }
        }
    }
}

struct BoxShadows: ViewModifier {
    let shadows: [Shadow]
    let shape: AnyShape

    init(_ value: CSSValue?, shape: AnyShape) {
        if case .shadows(let list)? = value { shadows = list } else { shadows = [] }
        self.shape = shape
    }

    func body(content: Content) -> some View {
        content.background {
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
}

struct ShadowMask: View {
    let shape: AnyShape

    var body: some View {
        Rectangle().padding(-1000).overlay { shape.blendMode(.destinationOut) }.compositingGroup()
    }
}
