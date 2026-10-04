import SwiftUI
import AppKit
import ApolloConfig
import ApolloStyle
import ApolloRuntime

enum FlyoutSide: String {
    case right, left, top, bottom

    var horizontal: Bool { self == .right || self == .left }

    static func resolve(_ value: String?, surfaceAnchor: String?) -> FlyoutSide {
        if let value, let side = FlyoutSide(rawValue: value) { return side }
        switch surfaceAnchor {
        case "right", "top-right", "bottom-right": return .left
        case "top": return .bottom
        case "bottom": return .top
        default: return .right
        }
    }
}

struct FlyoutBulge: Equatable {
    var key: String
    var rect: CGRect
    var side: FlyoutSide
    var radius: CGFloat
    var join: CGFloat
    var joined: Bool
    var open: Bool
    var container: CGSize
}

enum FlyoutGeometry {
    static let seed: CGFloat = 30

    static func clamp(_ wanted: CGFloat, length: CGFloat, limit: CGFloat) -> CGFloat {
        max(0, min(wanted, limit - length))
    }

    static func rect(side: FlyoutSide, anchor: CGRect, size: CGSize, container: CGSize, joined: Bool) -> CGRect {
        switch side {
        case .right:
            return CGRect(x: joined ? container.width : anchor.maxX, y: clamp(anchor.midY - size.height / 2, length: size.height, limit: container.height), width: size.width, height: size.height)
        case .left:
            return CGRect(x: (joined ? 0 : anchor.minX) - size.width, y: clamp(anchor.midY - size.height / 2, length: size.height, limit: container.height), width: size.width, height: size.height)
        case .bottom:
            return CGRect(x: clamp(anchor.midX - size.width / 2, length: size.width, limit: container.width), y: joined ? container.height : anchor.maxY, width: size.width, height: size.height)
        case .top:
            return CGRect(x: clamp(anchor.midX - size.width / 2, length: size.width, limit: container.width), y: (joined ? 0 : anchor.minY) - size.height, width: size.width, height: size.height)
        }
    }

    static func seed(side: FlyoutSide, anchor: CGRect, container: CGSize, joined: Bool) -> CGRect {
        switch side {
        case .right: CGRect(x: joined ? container.width : anchor.maxX, y: anchor.midY - seed / 2, width: 0, height: seed)
        case .left: CGRect(x: joined ? 0 : anchor.minX, y: anchor.midY - seed / 2, width: 0, height: seed)
        case .bottom: CGRect(x: anchor.midX - seed / 2, y: joined ? container.height : anchor.maxY, width: seed, height: 0)
        case .top: CGRect(x: anchor.midX - seed / 2, y: joined ? 0 : anchor.minY, width: seed, height: 0)
        }
    }

    static func extent(_ bulges: [FlyoutBulge]) -> EdgeInsets {
        var insets = EdgeInsets()
        for bulge in bulges where bulge.rect.width > 0.5 && bulge.rect.height > 0.5 {
            insets.leading = max(insets.leading, -bulge.rect.minX)
            insets.top = max(insets.top, -bulge.rect.minY)
            insets.trailing = max(insets.trailing, bulge.rect.maxX - bulge.container.width)
            insets.bottom = max(insets.bottom, bulge.rect.maxY - bulge.container.height)
        }
        return insets
    }
}

struct FlyoutBulgeKey: PreferenceKey {
    static let defaultValue: [FlyoutBulge] = []

    static func reduce(value: inout [FlyoutBulge], nextValue: () -> [FlyoutBulge]) {
        value += nextValue()
    }
}

struct FlyoutAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { first, _ in first }
    }
}

struct AnchorReport: ViewModifier {
    let id: String?

    func body(content: Content) -> some View {
        content.transformAnchorPreference(key: FlyoutAnchorKey.self, value: .bounds) { value, anchor in
            if let id, value[id] == nil { value[id] = anchor }
        }
    }
}

struct FusedShape: Shape {
    var radius: CGFloat
    var circular: Bool
    var bulges: [FlyoutBulge]

    var animatableData: RectVector {
        get { RectVector(bulges.flatMap { [$0.rect.minX, $0.rect.minY, $0.rect.width, $0.rect.height] }.map(Double.init)) }
        set {
            for index in bulges.indices where newValue.values.count >= index * 4 + 4 {
                let v = newValue.values[(index * 4)...]
                let base = index * 4
                bulges[index].rect = CGRect(x: v[base], y: v[base + 1], width: v[base + 2], height: v[base + 3])
            }
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = RoundedRectangle(cornerRadius: min(radius, min(rect.width, rect.height) / 2), style: circular ? .circular : .continuous).path(in: rect)
        for bulge in bulges where bulge.joined {
            path = path.union(Self.bulgePath(bulge, surface: rect))
        }
        return path
    }

    static func bulgePath(_ bulge: FlyoutBulge, surface rect: CGRect) -> Path {
        let b = bulge.rect
        guard b.width > 0.5, b.height > 0.5 else { return Path() }
        let r = min(bulge.radius, b.width / 2, b.height / 2)
        var path = Path()
        switch bulge.side {
        case .right: path.addRoundedRect(in: CGRect(x: b.minX - r, y: b.minY, width: b.width + r, height: b.height), cornerSize: CGSize(width: r, height: r))
        case .left: path.addRoundedRect(in: CGRect(x: b.minX, y: b.minY, width: b.width + r, height: b.height), cornerSize: CGSize(width: r, height: r))
        case .bottom: path.addRoundedRect(in: CGRect(x: b.minX, y: b.minY - r, width: b.width, height: b.height + r), cornerSize: CGSize(width: r, height: r))
        case .top: path.addRoundedRect(in: CGRect(x: b.minX, y: b.minY, width: b.width, height: b.height + r), cornerSize: CGSize(width: r, height: r))
        }
        let length = bulge.side.horizontal ? b.width : b.height
        func fillet(corner: CGPoint, along: CGVector, out: CGVector, room: CGFloat) {
            let j = min(bulge.join, length, max(0, room))
            guard j > 0.5 else { return }
            var fillet = Path()
            fillet.move(to: CGPoint(x: corner.x - along.dx * j, y: corner.y - along.dy * j))
            fillet.addQuadCurve(to: CGPoint(x: corner.x + out.dx * j, y: corner.y + out.dy * j), control: corner)
            fillet.addLine(to: corner)
            fillet.closeSubpath()
            path = path.union(fillet)
        }
        switch bulge.side {
        case .right:
            fillet(corner: CGPoint(x: rect.maxX, y: b.minY), along: CGVector(dx: 0, dy: 1), out: CGVector(dx: 1, dy: 0), room: b.minY - rect.minY)
            fillet(corner: CGPoint(x: rect.maxX, y: b.maxY), along: CGVector(dx: 0, dy: -1), out: CGVector(dx: 1, dy: 0), room: rect.maxY - b.maxY)
        case .left:
            fillet(corner: CGPoint(x: rect.minX, y: b.minY), along: CGVector(dx: 0, dy: 1), out: CGVector(dx: -1, dy: 0), room: b.minY - rect.minY)
            fillet(corner: CGPoint(x: rect.minX, y: b.maxY), along: CGVector(dx: 0, dy: -1), out: CGVector(dx: -1, dy: 0), room: rect.maxY - b.maxY)
        case .bottom:
            fillet(corner: CGPoint(x: b.minX, y: rect.maxY), along: CGVector(dx: 1, dy: 0), out: CGVector(dx: 0, dy: 1), room: b.minX - rect.minX)
            fillet(corner: CGPoint(x: b.maxX, y: rect.maxY), along: CGVector(dx: -1, dy: 0), out: CGVector(dx: 0, dy: 1), room: rect.maxX - b.maxX)
        case .top:
            fillet(corner: CGPoint(x: b.minX, y: rect.minY), along: CGVector(dx: 1, dy: 0), out: CGVector(dx: 0, dy: -1), room: b.minX - rect.minX)
            fillet(corner: CGPoint(x: b.maxX, y: rect.minY), along: CGVector(dx: -1, dy: 0), out: CGVector(dx: 0, dy: -1), room: rect.maxX - b.maxX)
        }
        return path
    }
}

struct RevealShape: Shape {
    var bulges: [FlyoutBulge]

    var animatableData: RectVector {
        get { FusedShape(radius: 0, circular: false, bulges: bulges).animatableData }
        set {
            var shape = FusedShape(radius: 0, circular: false, bulges: bulges)
            shape.animatableData = newValue
            bulges = shape.bulges
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for bulge in bulges where bulge.rect.width > 0.5 && bulge.rect.height > 0.5 {
            let r = min(bulge.radius, bulge.rect.width / 2, bulge.rect.height / 2)
            path.addRoundedRect(in: bulge.rect, cornerSize: CGSize(width: r, height: r))
        }
        return path
    }
}

struct RectVector: VectorArithmetic {
    var values: [Double]

    init(_ values: [Double]) {
        self.values = values
    }

    static var zero: RectVector { RectVector([]) }

    static func + (a: RectVector, b: RectVector) -> RectVector { combine(a, b, +) }
    static func - (a: RectVector, b: RectVector) -> RectVector { combine(a, b, -) }

    private static func combine(_ a: RectVector, _ b: RectVector, _ op: (Double, Double) -> Double) -> RectVector {
        let count = max(a.values.count, b.values.count)
        return RectVector((0..<count).map { op($0 < a.values.count ? a.values[$0] : 0, $0 < b.values.count ? b.values[$0] : 0) })
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}

struct FlyoutEntry {
    let element: ElementInstance
    let ancestors: [ElementInstance]
}

@MainActor
enum FlyoutCollector {
    static func collect(_ elements: [ElementInstance], ancestors: [ElementInstance] = []) -> [FlyoutEntry] {
        var result: [FlyoutEntry] = []
        for element in elements {
            if element.kind == "flyout" { result.append(FlyoutEntry(element: element, ancestors: ancestors)) }
            result += collect(element.children, ancestors: ancestors + [element])
        }
        return result
    }
}

struct SurfaceBox: ViewModifier {
    let surface: SurfaceInstance
    let style: ComputedStyle
    let context: RenderContext
    @State private var bulges: [FlyoutBulge] = []
    @Namespace private var matches

    func body(content: Content) -> some View {
        let flyouts = FlyoutCollector.collect(surface.root)
        let fused = surface.property("shape").plainText == "fused"
        let form: AnyShape? = fused && bulges.contains(where: \.joined)
            ? AnyShape(FusedShape(radius: StyleValues.radius(style["border-radius"]), circular: StyleValues.keyword(style["-apollo-corner-shape"]) == "circular", bulges: bulges))
            : nil
        let key = SurfaceHost.key(surface.id, surface.screenKey)
        let overlay = AnyView(FlyoutLayer(surface: surface, flyouts: flyouts, fused: fused, bulges: bulges, context: context))
        content
            .environment(\.matchNamespace, matches)
            .coordinateSpace(.named(matches))
            .modifier(StyledBox(style: style, context: context, form: form, flyouts: overlay,
                                dynamicInline: context.styles.declares("filter", StyleResolver.staticSubject(for: surface))))
            .animation(Self.motion(bulges, context: context), value: bulges)
            .onPreferenceChange(FlyoutBulgeKey.self) { new in
                bulges = new
                context.flyoutExtents[key] = FlyoutGeometry.extent(new)
                context.onFlyoutExtent(key, FlyoutGeometry.extent(new))
                context.onFlyoutBulges(key, new)
            }
    }

    @MainActor
    static func motion(_ bulges: [FlyoutBulge], context: RenderContext) -> Animation {
        .shellSpatial
    }
}

struct FlyoutLayer: View {
    let surface: SurfaceInstance
    let flyouts: [FlyoutEntry]
    let fused: Bool
    let bulges: [FlyoutBulge]
    let context: RenderContext

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(flyouts, id: \.element.identity) { entry in
                    FlyoutView(entry: entry, surface: surface, fused: fused, context: context, container: proxy.size)
                }
            }
            .mask(alignment: .topLeading) {
                RevealShape(bulges: bulges).frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
    }
}

struct FlyoutView: View {
    let entry: FlyoutEntry
    let surface: SurfaceInstance
    let fused: Bool
    let context: RenderContext
    let container: CGSize
    @State private var size: CGSize?
    @State private var monitor = FlyoutOutsideMonitor()
    @State private var slot = WindowSlot()
    @Environment(\.renderMode) private var renderMode
    @Environment(\.fusionOwnsBackground) private var fusionOwnsBackground

    var body: some View {
        let element = entry.element
        let (style, scope) = Self.resolve(entry, surface: surface, context: context)
        let open = element.property("open").isTruthy
        let joined = fused && element.property("join") != .bool(false)
        let side = FlyoutSide.resolve(element.property("side").plainText, surfaceAnchor: surface.property("anchor").plainText)
        let radius = StyleValues.radius(style["border-radius"])
        let join = StyleValues.points(style["-apollo-join-radius"]) ?? 14
        let boxStyle = joined ? Self.withoutPaint(style) : style
        let spatial = StyleMotion.transition(style, "size") ?? .shellSpatial
        AnchorResolver(id: element.property("anchor").plainText) { anchor in
            let measured = size ?? .zero
            let target = FlyoutGeometry.rect(side: side, anchor: anchor, size: measured, container: container, joined: joined)
            let bulge = open && size != nil ? target : FlyoutGeometry.seed(side: side, anchor: anchor, container: container, joined: joined)
            LayoutRenderers.flex(horizontal: false, style: style) {
                ElementChildren(children: element.children, scope: scope)
            }
                .modifier(StyledBox(style: boxStyle, context: context, dynamicInline: context.styles.declares("filter", StyleResolver.staticSubject(for: element))))
                .transformEnvironment(\.elementInteractive) { $0 = $0 && open }
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                .frame(width: target.width, height: target.height, alignment: .topLeading)
                .offset(x: target.minX, y: target.minY)
                .opacity(open ? 1 : 0)
                .animation(open ? (fusionOwnsBackground ? StatusFade.fadeIn.delay(StatusFade.fusedDelay) : StatusFade.fadeIn) : StatusFade.fadeOut, value: open)
                .allowsHitTesting(open)
                .accessibilityHidden(!open)
                .preference(key: FlyoutBulgeKey.self, value: [FlyoutBulge(key: element.identity.description, rect: bulge, side: side, radius: radius, join: join, joined: joined, open: open, container: container)])
                .animation(spatial, value: measured)
        }
        .background { WindowSlotReader(slot: slot) }
        .onChange(of: open) { _, now in
            if now, !renderMode { monitor.start(inside: { [slot] in slot.window }) { context.fire("on-close", element) } } else { monitor.stop() }
        }
        .onChange(of: container) { old, new in
            guard open, Self.thicknessChanged(old, new, anchor: surface.property("anchor").plainText) else { return }
            context.fire("on-close", element)
        }
        .onAppear { if open, !renderMode { monitor.start(inside: { [slot] in slot.window }) { context.fire("on-close", element) } } }
        .onDisappear { monitor.stop() }
    }

    static func thicknessChanged(_ old: CGSize, _ new: CGSize, anchor: String?) -> Bool {
        let width = abs(old.width - new.width) > 0.5, height = abs(old.height - new.height) > 0.5
        switch anchor {
        case "left", "right": return width
        case "top", "bottom": return height
        default: return width || height
        }
    }

    static func withoutPaint(_ style: ComputedStyle) -> ComputedStyle {
        ComputedStyle(values: style.values.filter { !["background", "background-color", "border", "box-shadow"].contains($0.key) })
    }

    @MainActor
    static func resolve(_ entry: FlyoutEntry, surface: SurfaceInstance, context: RenderContext) -> (ComputedStyle, RenderScope) {
        let styles = context.styles
        let surfaceSubject = StyleResolver.subject(for: surface)
        var parent = styles.resolve(surface: surface)
        var subjects = [surfaceSubject]
        for ancestor in entry.ancestors {
            let subject = StyleResolver.subject(for: ancestor)
            parent = styles.resolve(subject, ancestors: subjects, parent: parent, inline: ancestor.property("style").plainText)
            subjects.append(subject)
        }
        let subject = StyleResolver.subject(for: entry.element)
        let style = styles.resolve(subject, ancestors: subjects, parent: parent, inline: entry.element.property("style").plainText)
        return (style, RenderScope(context: context, ancestors: subjects + [subject], parentStyle: style, parentKind: "column"))
    }
}

enum StatusFade {
    static let fadeOut = Animation.timingCurve(0.34, 0.8, 0.34, 1, duration: 0.2)
    static let fadeIn = Animation.timingCurve(0.34, 0.88, 0.34, 1, duration: 0.3)
    static let fusedDelay: TimeInterval = 0.15
}

private struct FusionOwnsBackgroundKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var fusionOwnsBackground: Bool {
        get { self[FusionOwnsBackgroundKey.self] }
        set { self[FusionOwnsBackgroundKey.self] = newValue }
    }
}

struct AnchorResolver<Content: View>: View {
    let id: String?
    @ViewBuilder let content: (CGRect) -> Content
    @Environment(\.flyoutAnchors) private var anchors

    var body: some View {
        if let id, let rect = anchors[id] {
            content(rect)
        }
    }
}

struct FlyoutOverlay: ViewModifier {
    let layer: AnyView?

    func body(content: Content) -> some View {
        if let layer {
            content.overlayPreferenceValue(FlyoutAnchorKey.self, alignment: .topLeading) { anchors in
                GeometryReader { proxy in
                    layer.environment(\.flyoutAnchors, anchors.mapValues { proxy[$0] })
                }
            }
        } else {
            content
        }
    }
}

private struct FlyoutAnchorsKey: EnvironmentKey {
    static let defaultValue: [String: CGRect] = [:]
}

extension EnvironmentValues {
    var flyoutAnchors: [String: CGRect] {
        get { self[FlyoutAnchorsKey.self] }
        set { self[FlyoutAnchorsKey.self] = newValue }
    }
}

@MainActor
final class FlyoutOutsideMonitor {
    private var token: Any?
    private var localToken: Any?
    private let install: (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any?
    private let remove: (Any) -> Void

    init(install: @escaping (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any? = { NSEvent.addGlobalMonitorForEvents(matching: $0, handler: $1) },
         remove: @escaping (Any) -> Void = { NSEvent.removeMonitor($0) }) {
        self.install = install
        self.remove = remove
    }

    func start(inside window: @escaping @MainActor () -> NSWindow? = { nil }, _ onOutside: @escaping @MainActor () -> Void) {
        stop()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        token = install(mask) { _ in
            Task { @MainActor in onOutside() }
        }
        localToken = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            nonisolated(unsafe) let captured = event
            MainActor.assumeIsolated {
                if let own = window(), captured.window !== own { onOutside() }
            }
            return event
        }
    }

    func stop() {
        if let token { remove(token) }
        token = nil
        if let localToken { NSEvent.removeMonitor(localToken) }
        localToken = nil
    }
}
