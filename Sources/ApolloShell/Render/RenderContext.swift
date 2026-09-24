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

struct ElementView: View {
    let element: ElementInstance
    let scope: RenderScope

    var body: some View {
        let subject = StyleResolver.subject(for: element)
        let style = scope.context.styles.resolve(subject, ancestors: scope.ancestors, parent: scope.parentStyle, inline: element.property("style").plainText)
        let inner = RenderScope(context: scope.context, ancestors: scope.ancestors + [subject], parentStyle: style, parentKind: Self.layoutKind(element), outerKind: scope.parentKind)
        if element.property("visible") != .bool(false) {
            let spacer = element.kind == "spacer" && element.property("size") == .null
            let fill = Self.fill(style, parentKind: scope.parentKind, parentStyle: scope.parentStyle, spacer: spacer)
            ElementRenderers.view(for: element, style: style, scope: inner)
                .modifier(StyledBox(style: style, context: scope.context, padded: element.kind != "scroll", fill: fill, form: Self.form(element)))
                .layoutValue(key: ChildMetricsKey.self, value: ChildMetrics(style, spacer: spacer))
        }
    }
}

extension ElementView {
    static func layoutKind(_ element: ElementInstance) -> String {
        switch element.kind {
        case "reorderable": element.property("axis").plainText == "horizontal" ? "row" : "column"
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
        ForEach(children, id: \.identity) { child in
            ElementView(element: child, scope: scope)
        }
    }
}
