import SwiftUI
import AppKit
import ApolloShellCore
import ApolloConfig
import ApolloStyle
import ApolloRuntime

@MainActor
final class RenderContext {
    let styles: StyleResolver
    let icons: any AppIconSource
    let trigger: @MainActor (String, Identity, Record) -> Void
    var configRoot: URL?
    var themeIcon: @MainActor (String) -> NSImage? = { _ in nil }
    var theme: @MainActor (String) -> Theme? = { $0 == "default" ? .standard : nil }
    var imageValue: @MainActor (ImageRef) -> NSImage? = { _ in nil }
    var runtime: (any RenderRuntime)?
    var clock: any GateClock = SystemGateClock()
    var menus: any MenuPresenting = NativeMenuPresenter()
    var onRecording: @MainActor (Bool) -> Void = { _ in }
    var gates: [String: EventGate] = [:]
    var reorders: [String: ReorderCoordinator] = [:]
    var menuSources: [String: any MenuSourceProviding] = [:]
    var pending: [Task<Void, Never>] = []
    let hits = HitRegions()
    private var images: [String: NSImage] = [:]

    func image(for source: Value) -> NSImage? {
        switch source {
        case .image(let ref):
            return ref.source == "app-icon" ? icons.icon(for: source) : imageValue(ref)
        case .string(let path) where !path.isEmpty:
            if let cached = images[path] { return cached }
            guard let root = configRoot, let image = SafeImageFile.image(path, root: root) else { return nil }
            images[path] = image
            return image
        default:
            return nil
        }
    }

    init(styles: StyleResolver, icons: any AppIconSource, trigger: @escaping @MainActor (String, Identity, Record) -> Void) {
        self.styles = styles
        self.icons = icons
        self.trigger = trigger
    }
}

@MainActor
struct RenderScope {
    let context: RenderContext
    let ancestors: [StyleSubject]
    let parentStyle: ComputedStyle?
    let parentKind: String
    var outerKind = ""
}

@MainActor
enum ElementRenderers {
    typealias Factory = @MainActor (ElementInstance, ComputedStyle, RenderScope) -> AnyView

    static let table: [String: Factory] = [
        "column": LayoutRenderers.column,
        "row": LayoutRenderers.row,
        "stack": LayoutRenderers.stack,
        "reorderable": LayoutRenderers.reorderable,
        "toggle": InputRenderers.toggle,
        "slider": InputRenderers.slider,
        "input": InputRenderers.input,
        "key-recorder": InputRenderers.keyRecorder,
        "ring": DisplayRenderers.ring,
        "gauge": DisplayRenderers.gauge,
        "graph": DisplayRenderers.graph,
        "progress": DisplayRenderers.progress,
        "scroll": LayoutRenderers.scroll,
        "button": ControlRenderers.button,
        "app-icon": ImageRenderers.appIcon,
        "text": ContentRenderers.text,
        "icon": ContentRenderers.icon,
        "image": ContentRenderers.image,
        "shape": ContentRenderers.shape,
        "spacer": ContentRenderers.spacer,
        "grid": LayoutRenderers.grid,
        "theme-preview": ContentRenderers.themePreview,
        "mark": ContentRenderers.mark,
    ]

    static func view(for element: ElementInstance, style: ComputedStyle, scope: RenderScope) -> AnyView {
        guard let factory = table[element.kind] else { return AnyView(EmptyView()) }
        return factory(element, style, scope)
    }
}

struct ChildPosition: Equatable {
    var index: Int
    var count: Int
}

struct ElementView: View {
    let element: ElementInstance
    let scope: RenderScope
    var position: ChildPosition?
    var reorderEntry: ReorderEntry?

    var body: some View {
        let styles = scope.context.styles
        let subject = Self.subject(element, position: position)
        let inline = element.property("style").plainText
        let style = styles.resolve(subject, ancestors: scope.ancestors, parent: scope.parentStyle, inline: inline)
        let inner = RenderScope(context: scope.context, ancestors: scope.ancestors + [subject], parentStyle: style, parentKind: Self.layoutKind(element), outerKind: scope.parentKind)
        if element.property("visible") != .bool(false) {
            let spacer = element.kind == "spacer" && element.property("size") == .null
            let fill = Self.fill(style, parentKind: scope.parentKind, parentStyle: scope.parentStyle, spacer: spacer)
            let mouse = MouseConfig(element, reorder: reorderEntry)
            let hover = styles.sensitive(to: .hover, subject, ancestors: scope.ancestors, parent: scope.parentStyle, inline: inline) || element.kind == "button"
            ElementRenderers.view(for: element, style: style, scope: inner)
                .modifier(StyledBox(style: style, context: scope.context, padded: element.kind != "scroll", fill: fill, form: Self.form(element)))
                .modifier(HitRegionMarker(active: !mouse.isEmpty || StyleValues.visibleBackground(style), identity: element.identity))
                .modifier(InteractionIfNeeded(element: element, context: scope.context, config: mouse, hover: hover))
                .modifier(Motion(element: element, style: style, context: scope.context))
                .layoutValue(key: ChildMetricsKey.self, value: ChildMetrics(style, spacer: spacer))
        }
    }

    static func subject(_ element: ElementInstance, position: ChildPosition?) -> StyleSubject {
        var subject = StyleResolver.subject(for: element)
        if element.property("checked").isTruthy { subject.pseudo.insert(.checked) }
        if element.property("disabled").isTruthy { subject.pseudo.insert(.disabled) }
        if let position {
            if position.index == 0 { subject.pseudo.insert(.firstChild) }
            if position.index == position.count - 1 { subject.pseudo.insert(.lastChild) }
        }
        return subject
    }
}

struct InteractionIfNeeded: ViewModifier {
    let element: ElementInstance
    let context: RenderContext
    let config: MouseConfig
    let hover: Bool

    func body(content: Content) -> some View {
        let ir = element.ir
        let needed = !config.isEmpty || hover || !ir.handlers.isEmpty || !ir.accessibilityActions.isEmpty
            || element.property("tooltip") != .null || element.property("label") != .null
        if needed {
            content.modifier(ElementInteraction(element: element, context: context, config: config, hoverSensitive: hover))
        } else {
            content
        }
    }
}

extension ElementView {
    static func layoutKind(_ element: ElementInstance) -> String {
        switch element.kind {
        case "reorderable":
            switch element.property("axis").plainText {
            case "horizontal": "row"
            case "grid": "grid"
            default: "column"
            }
        default: element.kind
        }
    }

    static func form(_ element: ElementInstance) -> AnyShape? {
        guard element.kind == "shape" else { return nil }
        switch element.arguments.first?.value.stringified {
        case "circle": return AnyShape(Circle())
        case "capsule": return AnyShape(Capsule())
        case "scallop":
            let count = StyleValues.numberValue(element.property("count")).map(Int.init) ?? 8
            let depth = StyleValues.numberValue(element.property("depth")) ?? 0.2
            return AnyShape(ScallopShape(count: count, depth: depth))
        default: return nil
        }
    }

    static func fill(_ style: ComputedStyle, parentKind: String, parentStyle: ComputedStyle?, spacer: Bool = false) -> Definite {
        let horizontal: Bool
        switch parentKind {
        case "row": horizontal = true
        case "column": horizontal = false
        case "grid":
            let own = Definite(style)
            return Definite(width: !own.width, height: !own.height)
        default: return Definite()
        }
        let grows = (StyleValues.number(style["flex-grow"]) ?? 0) > 0 || spacer
        let own = StyleValues.keyword(style["align-self"])
        let inherited = StyleValues.keyword(parentStyle?["align-items"]) ?? "stretch"
        let stretches = (own == nil || own == "auto" ? inherited : own) == "stretch"
        let definite = Definite(style)
        let crossFree = horizontal ? !definite.height : !definite.width
        return horizontal ? Definite(width: grows, height: stretches && crossFree) : Definite(width: stretches && crossFree, height: grows)
    }
}

struct ElementChildren: View {
    let children: [ElementInstance]
    let scope: RenderScope

    var body: some View {
        ForEach(Array(children.enumerated()), id: \.element.identity) { index, child in
            ElementView(element: child, scope: scope, position: ChildPosition(index: index, count: children.count))
        }
    }
}
