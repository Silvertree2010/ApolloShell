import SwiftUI
import AppKit
import ApolloConfig
import ApolloStyle
import ApolloRuntime

struct MouseConfig: Equatable {
    var click = false
    var doubleClick = false
    var longPress = false
    var right = false
    var middle = false
    var scroll = false
    var accepts: Set<String> = []
    var menuOn: Set<String> = []
    var disabled = false
    var passive = false
    var inert = false
    var reorder: ReorderEntry?
    var canvas: CanvasEntry?
    var dragValue = false
    var gap = false

    init() {}

    @MainActor
    init(_ element: ElementInstance, reorder: ReorderEntry?, canvas: CanvasEntry? = nil) {
        let names = Set(element.ir.handlers.map(\.name))
        click = names.contains("on-click")
        doubleClick = names.contains("on-double-click")
        longPress = names.contains("on-long-press")
        right = names.contains("on-right-click")
        middle = names.contains("on-middle-click")
        scroll = names.contains("on-scroll")
        if element.kind != "reorderable", names.contains("on-drop"), let handler = element.ir.handlers.first(where: { $0.name == "on-drop" }),
           let accept = handler.properties["accept"].flatMap(HandlerRules.literal)?.plainText {
            accepts = [accept]
        }
        if element.kind == "reorderable", element.ir.handlers.contains(where: { $0.name == "on-drop" }), element.property("accept").plainText == "value" {
            gap = true
        }
        if element.ir.menu != nil {
            let text = element.property("menu-on").plainText ?? "right-click"
            menuOn = Set(text.split(whereSeparator: \.isWhitespace).map(String.init))
        }
        disabled = element.property("disabled").isTruthy
        self.reorder = reorder
        self.canvas = canvas?.enabled == true ? canvas : nil
        dragValue = element.property("drag-value") != .null
    }

    var isEmpty: Bool {
        !click && !doubleClick && !longPress && !right && !middle && !scroll && accepts.isEmpty && menuOn.isEmpty && reorder == nil && canvas == nil && !dragValue && !gap && !passive
    }

    func claims(_ kind: MouseKind) -> Bool {
        if inert { return false }
        if passive { return kind != .scroll }
        switch kind {
        case .left: return click || doubleClick || longPress || right || !menuOn.isEmpty || reorder != nil || canvas != nil || dragValue
        case .right: return right || menuOn.contains("right-click")
        case .middle: return middle
        case .scroll: return scroll
        case .drag: return !accepts.isEmpty || reorder != nil || gap
        }
    }

    var hasMenuOnSecondary: Bool { menuOn.contains("right-click") }
}

enum MouseKind {
    case left, right, middle, scroll, drag

    static func current(_ event: NSEvent?) -> MouseKind {
        switch event?.type {
        case .rightMouseDown?, .rightMouseUp?, .rightMouseDragged?: .right
        case .otherMouseDown?, .otherMouseUp?, .otherMouseDragged?: .middle
        case .scrollWheel?: .scroll
        case .leftMouseDown?, .leftMouseUp?, .leftMouseDragged?: .left
        default: .drag
        }
    }
}

enum EventFields {
    static func modifiers(_ flags: NSEvent.ModifierFlags) -> Value {
        var names: [Value] = []
        if flags.contains(.command) { names.append(.string("cmd")) }
        if flags.contains(.option) { names.append(.string("alt")) }
        if flags.contains(.shift) { names.append(.string("shift")) }
        if flags.contains(.control) { names.append(.string("ctrl")) }
        return .list(names)
    }

    static func phase(_ event: NSEvent) -> String {
        let phase = event.phase.isEmpty ? event.momentumPhase : event.phase
        if phase.contains(.began) || phase.contains(.mayBegin) { return "began" }
        if phase.contains(.ended) || phase.contains(.cancelled) { return "ended" }
        if phase.contains(.changed) || phase.contains(.stationary) { return "changed" }
        return "none"
    }

    static func drop(_ pasteboard: NSPasteboard, accept: String) -> Record? {
        switch accept {
        case "files":
            let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            guard !urls.isEmpty else { return nil }
            return Record([("files", .list(urls.map { .string($0.path) }))])
        case "apps":
            var ids: [String] = []
            if let id = pasteboard.string(forType: .apolloApp) { ids.append(id) }
            let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            ids += urls.filter { $0.pathExtension == "app" }.compactMap { Bundle(url: $0)?.bundleIdentifier }
            guard !ids.isEmpty else { return nil }
            return Record([("apps", .list(ids.map { .string($0) }))])
        case "text":
            guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return nil }
            return Record([("text", .string(text))])
        case "value":
            guard let token = pasteboard.string(forType: .apolloValue), let value = MainActor.assumeIsolated({ DragValues.value(token) }) else { return nil }
            return Record([("value", value)])
        default:
            return nil
        }
    }

    static func types(_ accepts: Set<String>) -> [NSPasteboard.PasteboardType] {
        var result: [NSPasteboard.PasteboardType] = []
        if accepts.contains("files") || accepts.contains("apps") { result.append(.fileURL) }
        if accepts.contains("apps") { result.append(.apolloApp) }
        if accepts.contains("text") { result.append(.string) }
        if accepts.contains("value") { result.append(.apolloValue) }
        return result
    }
}

extension NSPasteboard.PasteboardType {
    static let apolloApp = NSPasteboard.PasteboardType("to.apollocloud.apolloshell.app")
    static let apolloReorder = NSPasteboard.PasteboardType("to.apollocloud.apolloshell.reorder")
    static let apolloValue = NSPasteboard.PasteboardType("to.apollocloud.apolloshell.value")
}

struct ElementInteraction: ViewModifier {
    let element: ElementInstance
    let context: RenderContext
    let config: MouseConfig
    let hoverSensitive: Bool
    var pressSensitive = false
    @Environment(\.elementInteractive) private var interactive

    func body(content: Content) -> some View {
        let tooltip = element.property("tooltip").plainText
        let label = element.property("label").plainText ?? tooltip
        var config = config
        config.inert = !interactive
        let pressing = pressSensitive && interactive && !config.claims(.left)
        let hoverWatched = hoverSensitive || element.ir.handlers.contains { $0.name == "on-hover" || $0.name == "on-hover-end" }
        return content
            .gated(hoverWatched) { $0.modifier(HoverTracking(element: element, context: context, active: interactive && hoverWatched)) }
            .gated(pressSensitive) { $0.modifier(PressTracking(element: element, including: pressing ? .all : .subviews)) }
            .overlay {
                if !config.isEmpty {
                    MouseCatcher(element: element, context: context, config: config)
                }
            }
            .onAppear { context.fire("on-appear", element) }
            .onDisappear {
                context.fire("on-disappear", element)
                context.forget(element)
                if element.pseudo.contains(.hover) || element.pseudo.contains(.active) {
                    element.pseudo.subtract([.hover, .active])
                }
            }
            .gated(element.ir.properties["tooltip"] != nil) { $0.modifier(OptionalHelp(text: tooltip)) }
            .gated(element.ir.properties["label"] != nil || element.ir.properties["tooltip"] != nil || config.click || !element.ir.accessibilityActions.isEmpty) {
                $0.modifier(AccessibilityActions(element: element, context: context, label: label, config: config))
            }
    }
}

struct PressTracking: ViewModifier {
    let element: ElementInstance
    let including: GestureMask
    @GestureState private var pressed = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(DragGesture(minimumDistance: 0).updating($pressed) { _, state, _ in state = true }, including: including)
            .onChange(of: pressed) { _, now in Self.apply(now, to: element) }
    }

    static func apply(_ pressed: Bool, to element: ElementInstance) {
        if pressed {
            if !element.pseudo.contains(.active) { element.pseudo.insert(.active) }
        } else if element.pseudo.contains(.active) {
            element.pseudo.remove(.active)
        }
    }
}

struct HoverTracking: ViewModifier {
    let element: ElementInstance
    let context: RenderContext
    let active: Bool

    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside {
                guard active else { return }
                element.pseudo.insert(.hover)
                context.fire("on-hover", element)
            } else if active || element.pseudo.contains(.hover) {
                element.pseudo.remove(.hover)
                context.fire("on-hover-end", element)
            }
        }
    }
}

struct OptionalHelp: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        content.help(text ?? "")
    }
}

struct AccessibilityActions: ViewModifier {
    let element: ElementInstance
    let context: RenderContext
    let label: String?
    let config: MouseConfig

    func body(content: Content) -> some View {
        let named = element.ir.accessibilityActions
        var view = AnyView(content.accessibilityLabel(Text(label ?? ""), isEnabled: label != nil))
        if config.click {
            view = AnyView(view.accessibilityAction { context.fire("on-click", element, Record([("modifiers", .list([]))])) })
        }
        for (index, action) in named.enumerated() {
            let title = context.runtime?.evaluate(action.title, on: element.identity, locals: [:]).plainText
                ?? HandlerRules.literal(action.title)?.plainText ?? ""
            view = AnyView(view.accessibilityAction(named: Text(title)) {
                context.runtime?.run(action.actions, on: element.identity, site: "accessibility#\(index)", event: Record(), locals: [:])
            })
        }
        return view
    }
}

struct MouseCatcher: NSViewRepresentable {
    let element: ElementInstance
    let context: RenderContext
    let config: MouseConfig

    func makeNSView(context: Context) -> ElementMouseView {
        let view = ElementMouseView()
        update(view)
        return view
    }

    func updateNSView(_ view: ElementMouseView, context: Context) {
        update(view)
    }

    private func update(_ view: ElementMouseView) {
        view.element = element
        view.renderContext = context
        view.config = config
    }
}

@MainActor
final class ElementMouseView: NSView, NSDraggingSource {
    private static var live: [WeakMouseView] = []
    private static let dragThreshold: CGFloat = 4
    static let sourceMask: NSDragOperation = [.move, .copy]

    weak var element: ElementInstance?
    weak var renderContext: RenderContext?
    var config = MouseConfig() {
        didSet {
            guard config != oldValue else { return }
            var types = EventFields.types(config.accepts) + (config.reorder != nil ? [.apolloReorder] : [])
            if config.reorder?.coordinator?.accept == "value" || config.gap { types.append(.apolloValue) }
            unregisterDraggedTypes()
            if !types.isEmpty { registerForDraggedTypes(types) }
        }
    }

    private var holdWork: DispatchWorkItem?
    private var longPressed = false
    private var downPoint: NSPoint?
    private var dragging = false
    private var canvasDrag: (resize: Bool, start: NSPoint)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        Self.live.append(WeakMouseView(view: self))
    }

    required init?(coder: NSCoder) {
        fatalError("not from a nib")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let window, !isHidden, !config.disabled else { return nil }
        let kind = MouseKind.current(NSApp.currentEvent)
        guard config.claims(kind), let superview else { return nil }
        let local = convert(point, from: superview)
        guard bounds.intersection(visibleRect).contains(local) else { return nil }
        let inWindow = convert(local, to: nil)
        let winner = Self.winner(at: inWindow, in: window, kind: kind)
        return winner === self && !config.passive ? self : nil
    }

    func entries(of c: ReorderCoordinator) -> [(Int, NSRect)] {
        Self.live.compactMap { w in
            guard let v = w.view, v.window === window, let r = v.config.reorder, r.coordinator === c else { return nil }
            return (r.index, v.convert(v.bounds, to: nil))
        }
    }

    static func winner(at point: NSPoint, in window: NSWindow, kind: MouseKind) -> ElementMouseView? {
        live.removeAll { $0.view == nil }
        var best: ElementMouseView?
        var bestArea = CGFloat.infinity
        for entry in live {
            guard let view = entry.view, view.window === window, !view.isHiddenOrHasHiddenAncestor, view.config.claims(kind) else { continue }
            let frame = view.convert(view.bounds, to: nil)
            guard frame.intersection(view.convert(view.visibleRect, to: nil)).contains(point) else { continue }
            let area = frame.width * frame.height
            if area <= bestArea {
                best = view
                bestArea = area
            }
        }
        return best
    }

    override func mouseDown(with event: NSEvent) {
        guard let element, let context = renderContext else { return }
        if event.modifierFlags.contains(.control) {
            secondary(event)
            return
        }
        longPressed = false
        dragging = false
        downPoint = event.locationInWindow
        element.pseudo.insert(.active)
        if config.longPress || config.menuOn.contains("long-press") {
            let delay = context.rules(element, "on-long-press").delay ?? 0.5
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.longPress() }
            }
            holdWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    func longPress() {
        guard let element, let context = renderContext, !dragging else { return }
        holdWork = nil
        longPressed = true
        element.pseudo.remove(.active)
        context.fire("on-long-press", element)
        if config.menuOn.contains("long-press") { context.menus.present(element, context: context, from: self, at: nil) }
    }

    override func mouseDragged(with event: NSEvent) {
        if let canvas = config.canvas, let start = downPoint, !longPressed {
            let point = event.locationInWindow
            if canvasDrag == nil {
                guard hypot(point.x - start.x, point.y - start.y) > 2 else { return }
                holdWork?.cancel()
                holdWork = nil
                dragging = true
                element?.pseudo.remove(.active)
                let local = convert(start, from: nil)
                let fromBottom = isFlipped ? bounds.height - local.y : local.y
                let grip = CanvasEntry.grip * canvas.scale
                canvasDrag = (local.x >= bounds.width - grip && fromBottom <= grip && canvas.coordinator?.container.ir.handlers.contains { $0.name == "on-resize" } == true, start)
            }
            guard let drag = canvasDrag else { return }
            canvas.coordinator?.drag(canvas.key, dx: (point.x - drag.start.x) / canvas.scale, dy: (drag.start.y - point.y) / canvas.scale, resize: drag.resize, ended: false)
            return
        }
        if config.dragValue, config.reorder == nil, let element, let start = downPoint, !dragging, !longPressed {
            let point = event.locationInWindow
            guard hypot(point.x - start.x, point.y - start.y) > Self.dragThreshold else { return }
            dragging = true
            holdWork?.cancel()
            holdWork = nil
            element.pseudo.remove(.active)
            let item = NSPasteboardItem()
            item.setString(DragValues.store(element.property("drag-value")), forType: .apolloValue)
            let dragItem = NSDraggingItem(pasteboardWriter: item)
            dragItem.setDraggingFrame(bounds, contents: snapshot())
            beginDraggingSession(with: [dragItem], event: event, source: self)
            return
        }
        guard let start = downPoint, !dragging, !longPressed, let reorder = config.reorder, reorder.enabled else { return }
        let point = event.locationInWindow
        guard hypot(point.x - start.x, point.y - start.y) > Self.dragThreshold else { return }
        dragging = true
        holdWork?.cancel()
        holdWork = nil
        element?.pseudo.remove(.active)
        let item = NSPasteboardItem()
        item.setString(reorder.token, forType: .apolloReorder)
        if let element, element.property("drag-value") != .null { item.setString(DragValues.store(element.property("drag-value")), forType: .apolloValue) }
        if let app = reorder.app { item.setString(app, forType: .apolloApp) }
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        dragItem.setDraggingFrame(bounds, contents: snapshot())
        reorder.coordinator?.begin(reorder)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    func snapshot() -> NSImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        superview?.cacheDisplay(in: frame, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    override func mouseUp(with event: NSEvent) {
        holdWork?.cancel()
        holdWork = nil
        downPoint = nil
        element?.pseudo.remove(.active)
        if let drag = canvasDrag, let canvas = config.canvas {
            let point = event.locationInWindow
            canvasDrag = nil
            dragging = false
            canvas.coordinator?.drag(canvas.key, dx: (point.x - drag.start.x) / canvas.scale, dy: (drag.start.y - point.y) / canvas.scale, resize: drag.resize, ended: true)
            return
        }
        if dragging {
            dragging = false
            return
        }
        guard !longPressed, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        primary(event.modifierFlags, count: event.clickCount)
    }

    func primary(_ flags: NSEvent.ModifierFlags, count: Int) {
        guard let element, let context = renderContext else { return }
        let fields = Record([("modifiers", EventFields.modifiers(flags))])
        if count >= 2, config.doubleClick {
            context.fire("on-double-click", element, fields)
            return
        }
        let menu = config.menuOn.contains("click")
        if !menu || !config.click {
            context.fire("on-click", element, fields)
        }
        if menu { context.menus.present(element, context: context, from: self, at: nil) }
    }

    override func rightMouseDown(with event: NSEvent) {
        secondary(event)
    }

    func secondary(_ event: NSEvent?) {
        guard let element, let context = renderContext else { return }
        context.fire("on-right-click", element, Record([("modifiers", EventFields.modifiers(event?.modifierFlags ?? []))]))
        if config.hasMenuOnSecondary {
            let point = event.map { convert($0.locationInWindow, from: nil) }
            context.menus.present(element, context: context, from: self, at: point)
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2, let element, let context = renderContext else {
            super.otherMouseDown(with: event)
            return
        }
        context.fire("on-middle-click", element, Record([("modifiers", EventFields.modifiers(event.modifierFlags))]))
    }

    override func scrollWheel(with event: NSEvent) {
        guard config.scroll, let element, let context = renderContext, !scrollsAncestor() else {
            super.scrollWheel(with: event)
            return
        }
        context.fire("on-scroll", element, Record([
            ("dx", .number(Double(event.scrollingDeltaX))),
            ("dy", .number(Double(event.scrollingDeltaY))),
            ("phase", .string(EventFields.phase(event))),
            ("precise", .bool(event.hasPreciseScrollingDeltas)),
        ]))
    }

    private func scrollsAncestor() -> Bool {
        guard let scrollView = enclosingScrollView, let document = scrollView.documentView else { return false }
        return document.frame.height > scrollView.contentView.bounds.height + 1 || document.frame.width > scrollView.contentView.bounds.width + 1
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        Self.sourceMask
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard let reorder = config.reorder else { return }
        let inside = window.map { $0.frame.contains(screenPoint) } ?? false
        reorder.coordinator?.end(reorder, droppedOutside: !inside && operation == [])
    }

    private func inner(_ sender: NSDraggingInfo) -> ElementMouseView? {
        guard let window, let w = Self.winner(at: sender.draggingLocation, in: window, kind: .drag), w !== self else { return nil }
        return w
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        inner(sender)?.operation(for: sender) ?? operation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        inner(sender)?.operation(for: sender) ?? operation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let w = inner(sender) { return w.performDragOperation(sender) }
        guard let element, let context = renderContext else { return false }
        let pasteboard = sender.draggingPasteboard
        if let token = pasteboard.string(forType: .apolloReorder), let reorder = config.reorder, reorder.coordinator?.accepts(token: token, on: reorder) == true {
            return reorder.coordinator?.drop(token: token, on: reorder) ?? false
        }
        for accept in config.accepts.sorted() {
            if var fields = EventFields.drop(pasteboard, accept: accept) {
                let local = convert(sender.draggingLocation, from: nil)
                let scale = element.kind == "canvas" ? context.canvas(for: element).scale : 1
                fields["x"] = .number(Double(local.x) / scale)
                fields["y"] = .number(Double(isFlipped ? local.y : bounds.height - local.y) / scale)
                context.fire("on-drop", element, fields)
                return true
            }
        }
        if let reorder = config.reorder, let coordinator = reorder.coordinator {
            return coordinator.foreignDrop(pasteboard, on: reorder)
        }
        if config.gap {
            let c = context.coordinator(for: element)
            return c.gapDrop(pasteboard, at: sender.draggingLocation, in: self)
        }
        return false
    }

    private func operation(for info: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = info.draggingPasteboard
        if let token = pasteboard.string(forType: .apolloReorder), let reorder = config.reorder, reorder.coordinator?.accepts(token: token, on: reorder) == true {
            return .move
        }
        for accept in config.accepts where EventFields.drop(pasteboard, accept: accept) != nil {
            return .copy
        }
        if let reorder = config.reorder, reorder.coordinator?.acceptsForeign(pasteboard) == true { return .copy }
        if config.gap, let element, let context = renderContext, context.coordinator(for: element).acceptsForeign(pasteboard) { return .copy }
        return []
    }
}

private struct WeakMouseView {
    weak var view: ElementMouseView?
}
