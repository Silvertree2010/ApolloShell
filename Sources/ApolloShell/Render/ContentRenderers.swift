import SwiftUI
import AppKit
import ApolloConfig
import ApolloStyle
import ApolloRuntime
import ApolloShellCore

@MainActor
enum ContentRenderers {
    static func text(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        AnyView(TextElement(content: element.arguments.first?.value.stringified ?? "", element: element, style: style))
    }

    static func icon(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        let name = element.arguments.first?.value.stringified ?? ""
        let variable = StyleValues.numberValue(element.property("variable"))
        return AnyView(IconElement(name: name, fallback: element.property("fallback").plainText, variable: variable,
                                   style: style, context: scope.context))
    }

    static func image(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        let source = element.arguments.first?.value ?? .null
        let image = scope.context.image(for: source)
        let fit = element.property("fit").plainText ?? "fit"
        let placeholder = element.property("placeholder").plainText
        return AnyView(ImageElement(image: image, fit: fit, placeholder: placeholder, style: style, context: scope.context))
    }

    static func shape(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        AnyView(Color.clear)
    }

    static func spacer(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        if let size = StyleValues.numberValue(element.property("size")) {
            let horizontal = scope.outerKind == "row"
            return AnyView(Color.clear.frame(width: horizontal ? size : nil, height: horizontal ? nil : size))
        }
        return AnyView(Color.clear.frame(minWidth: 0, minHeight: 0))
    }

    static func themePreview(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        let theme = scope.context.previewTheme(element.property("theme"))
        let forced = element.property("appearance").plainText
        return AnyView(ThemePreviewElement(theme: theme, forced: forced))
    }

    static func mark(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        let reaction = EmblemReaction(rawValue: element.property("state").plainText ?? "idle") ?? .idle
        let greet = element.property("greet") != .bool(false)
        var accent = Color.accentColor
        if case .color(let value)? = style["accent-color"] { accent = StyleValues.color(value) }
        if let explicit = element.property("color").plainText, let parsed = scope.context.styles.parseColor(explicit) { accent = StyleValues.color(parsed) }
        var track: Color?
        if case .color(let value)? = style["-apollo-track-color"] { track = StyleValues.color(value) }
        let size = StyleValues.points(style["width"]) ?? 80
        if let themed = scope.context.themeIcon("session-emblem") {
            return AnyView(Image(nsImage: themed).resizable().scaledToFit().frame(width: size, height: size))
        }
        return AnyView(MarkElement(reaction: reaction, greet: greet, accent: accent, track: track, size: size))
    }
}

struct TextElement: View {
    let content: String
    let element: ElementInstance
    let style: ComputedStyle

    var body: some View {
        let text = TextStyle(style)
        let lines = StyleValues.count(element.property("lines"), limit: 100_000) ?? 1
        Text(content)
            .font(text.font)
            .foregroundStyle(text.color)
            .tracking(text.tracking)
            .lineSpacing(text.lineSpacing)
            .multilineTextAlignment(text.alignment)
            .lineLimit(lines == 0 ? nil : lines)
            .truncationMode(Self.truncation(element.property("truncate").plainText))
            .minimumScaleFactor(StyleValues.numberValue(element.property("min-scale")).map { min(max($0, 0.01), 1) } ?? 1)
            .modifier(ContentTransition(style["-apollo-content-transition"]))
            .accessibilityLabel(element.property("label").plainText ?? content)
    }

    static func truncation(_ value: String?) -> Text.TruncationMode {
        switch value {
        case "middle": .middle
        case "head": .head
        default: .tail
        }
    }
}

struct ContentTransition: ViewModifier {
    let kind: String?

    init(_ value: CSSValue?) {
        kind = StyleValues.keyword(value)
    }

    func body(content: Content) -> some View {
        switch kind {
        case "numeric": content.contentTransition(.numericText())
        case "opacity": content.contentTransition(.opacity)
        case "symbol": content.contentTransition(.symbolEffect(.replace))
        case "none": content.contentTransition(.identity)
        default: content
        }
    }
}

enum BuiltinIcon {
    static let names: Set<String> = ["builtin:bluetooth-rune", "builtin:apollo-mark", "builtin:file-manager-folder"]
}

struct IconElement: View {
    let name: String
    let fallback: String?
    let variable: Double?
    let style: ComputedStyle
    let context: RenderContext

    var body: some View {
        let text = TextStyle(style)
        Group {
            if let image = context.themeIcon(name) {
                let template = context.styles.environment.tokens.iconsMonochrome
                Image(nsImage: image)
                    .renderingMode(template ? .template : .original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: text.size * 1.2, height: text.size * 1.2)
            } else if let target = Self.builtinTarget(name, fallback: fallback) {
                builtin(target, size: text.size)
            } else {
                Image(systemName: Self.symbol(name, fallback: fallback), variableValue: variable)
                    .font(text.font)
                    .symbolRenderingMode(Self.rendering(style["-apollo-symbol-rendering"]))
                    .modifier(SymbolEffect(style["-apollo-symbol-effect"]))
            }
        }
        .foregroundStyle(text.color)
        .modifier(ContentTransition(style["-apollo-content-transition"]))
    }

    @ViewBuilder
    func builtin(_ name: String, size: CGFloat) -> some View {
        switch name {
        case "builtin:bluetooth-rune":
            BluetoothRune()
                .stroke(style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.77, height: size * 1.15)
        case "builtin:apollo-mark":
            ApolloMark().frame(width: size * 1.2, height: size * 1.2)
        case "builtin:file-manager-folder":
            Image(nsImage: BuiltinArt.folder).resizable().frame(width: size * 1.2, height: size * 1.2)
        default:
            Image(systemName: Self.symbol("", fallback: fallback)).font(TextStyle(style).font)
        }
    }

    static func builtinTarget(_ name: String, fallback: String?) -> String? {
        if name.hasPrefix("builtin:") { return name }
        guard let fallback, fallback.hasPrefix("builtin:") else { return nil }
        if !name.isEmpty, NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil { return nil }
        return fallback
    }

    static func symbol(_ name: String, fallback: String?) -> String {
        if !name.isEmpty, NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil { return name }
        if let fallback, NSImage(systemSymbolName: fallback, accessibilityDescription: nil) != nil { return fallback }
        return "questionmark.square.dashed"
    }

    static func rendering(_ value: CSSValue?) -> SymbolRenderingMode {
        switch StyleValues.keyword(value) {
        case "hierarchical": .hierarchical
        case "palette": .palette
        case "multicolor": .multicolor
        default: .monochrome
        }
    }
}

struct SymbolEffect: ViewModifier {
    let kind: String?
    @Environment(\.renderMode) private var renderMode
    @Environment(\.surfaceShown) private var shown

    init(_ value: CSSValue?) {
        kind = StyleValues.keyword(value)
    }

    func body(content: Content) -> some View {
        switch renderMode || !shown ? nil : kind {
        case "variable-color": content.symbolEffect(.variableColor.iterative, options: .repeating)
        case "pulse": content.symbolEffect(.pulse, options: .repeating)
        case "bounce": content.symbolEffect(.bounce, options: .repeating)
        default: content
        }
    }
}

struct BluetoothRune: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        path.move(to: p(0, 0.27))
        path.addLine(to: p(1, 0.73))
        path.addLine(to: p(0.5, 1))
        path.addLine(to: p(0.5, 0))
        path.addLine(to: p(1, 0.27))
        path.addLine(to: p(0, 0.73))
        return path
    }
}

@MainActor
enum BuiltinArt {
    static let folder: NSImage = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
        let side = rect.width * 0.82
        let tile = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        let shape = NSBezierPath(roundedRect: tile, xRadius: side * 0.225, yRadius: side * 0.225)
        NSGradient(starting: NSColor(white: 0.62, alpha: 1), ending: NSColor(white: 0.55, alpha: 1))?.draw(in: shape, angle: -90)
        NSColor(white: 1, alpha: 0.18).setStroke()
        shape.lineWidth = rect.width * 0.012
        shape.stroke()
        let config = NSImage.SymbolConfiguration(pointSize: side * 0.46, weight: .medium)
            .applying(.init(paletteColors: [NSColor(white: 0.97, alpha: 1)]))
        if let glyph = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let size = glyph.size
            glyph.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        }
        return true
    }
}

struct ImageElement: View {
    let image: NSImage?
    let fit: String
    let placeholder: String?
    let style: ComputedStyle
    let context: RenderContext

    var body: some View {
        if let image {
            let template = StyleValues.keyword(style["-apollo-image-rendering"]) == "template"
            let base = Image(nsImage: image).renderingMode(template ? .template : .original)
            Group {
                switch fit {
                case "fill":
                    Color.clear
                        .overlay { base.resizable().interpolation(.high).scaledToFill() }
                case "stretch": base.resizable().interpolation(.high)
                case "center": base
                default: base.resizable().interpolation(.high).scaledToFit()
                }
            }
            .foregroundStyle(TextStyle(style).color)
            .clipShape(RoundedRectangle(cornerRadius: StyleValues.radius(style["border-radius"]), style: .continuous))
        } else if let placeholder {
            IconElement(name: placeholder, fallback: nil, variable: nil, style: style, context: context)
        } else {
            Color.clear
        }
    }
}

struct ScallopShape: Shape {
    var count: Int
    var depth: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        guard count > 0, depth > 0 else { return Circle().path(in: rect) }
        var path = Path()
        let steps = max(count * 24, 96)
        for step in 0...steps {
            let angle = Double(step) / Double(steps) * 2 * .pi - .pi / 2
            let wave = (1 + cos(Double(count) * (angle + .pi / 2))) / 2
            let r = radius * (1 - depth * (1 - wave))
            let point = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

struct ThemePreviewElement: View {
    let theme: Theme
    let forced: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ThemePreview(theme: theme, dark: forced.map { $0 == "dark" } ?? (scheme == .dark))
    }
}

struct MarkElement: View {
    let reaction: EmblemReaction
    let greet: Bool
    let accent: Color
    let track: Color?
    let size: CGFloat
    @State private var timeline: EmblemTimeline?
    @Environment(\.renderMode) private var renderMode
    @Environment(\.markRenderTime) private var markRenderTime
    @Environment(\.surfaceShown) private var shown

    static func onShow(_ shown: Bool, greet: Bool, reaction: EmblemReaction, at time: TimeInterval) -> EmblemTimeline? {
        shown ? EmblemTimeline(greet ? .greet : reaction, at: time) : nil
    }

    var opening: EmblemReaction {
        greet && !(renderMode && reaction != .idle) ? .greet : reaction
    }

    var body: some View {
        let current = timeline ?? EmblemTimeline(opening, at: 0)
        SessionEmblem(timeline: current, size: size, animating: !renderMode && shown,
                      fixedTime: renderMode ? current.startTime + markRenderTime : nil, accent: accent, track: track)
            .onAppear {
                if timeline == nil {
                    timeline = EmblemTimeline(opening, at: Date.timeIntervalSinceReferenceDate)
                }
            }
            .onChange(of: shown) { _, now in
                if let next = Self.onShow(now, greet: greet, reaction: reaction, at: Date.timeIntervalSinceReferenceDate) { timeline = next }
            }
            .onChange(of: reaction) { _, next in
                timeline?.show(next, at: Date.timeIntervalSinceReferenceDate)
            }
    }
}
