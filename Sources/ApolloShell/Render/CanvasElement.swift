import SwiftUI
import AppKit
import Observation
import ApolloConfig
import ApolloStyle
import ApolloRuntime

struct CanvasEntry: Equatable {
    let key: Value
    let enabled: Bool
    let scale: Double
    weak var coordinator: CanvasCoordinator?

    static let grip: Double = 28

    static func == (a: CanvasEntry, b: CanvasEntry) -> Bool {
        a.key == b.key && a.enabled == b.enabled && a.scale == b.scale && a.coordinator === b.coordinator
    }
}

struct CanvasItem {
    var key: Value
    var frame: CanvasFrame
    var sizes: [CanvasSize]
}

@MainActor
@Observable
final class CanvasCoordinator {
    let container: ElementInstance
    @ObservationIgnored weak var context: RenderContext?
    var live: [Value: (frame: CanvasFrame, valid: Bool)] = [:]
    @ObservationIgnored var pageSize = CGSize.zero
    @ObservationIgnored private var generation: [Value: Int] = [:]

    init(container: ElementInstance, context: RenderContext) {
        self.container = container
        self.context = context
    }

    var enabled: Bool { container.property("enabled").isTruthy }

    var scale: Double {
        guard case .number(let value) = container.property("scale"), value.isFinite, value > 0 else { return 1 }
        return value
    }

    var geometry: CanvasGeometry {
        func number(_ name: String, _ fallback: Double) -> Double {
            if case .number(let value) = container.property(name), value.isFinite, value >= 0 { return value }
            return fallback
        }
        let items = self.items.map(\.frame)
        let width = pageSize.width > 0 ? pageSize.width / scale : items.map(\.maxX).max() ?? 0
        let height = pageSize.height > 0 ? pageSize.height / scale : items.map(\.maxY).max() ?? 0
        return CanvasGeometry(width: width, height: height, gap: number("gap", 12), snap: number("snap", 8))
    }

    var eachVariable: String? {
        for case .each(let each) in container.ir.children { return each.variable }
        return nil
    }

    func item(for child: ElementInstance) -> CanvasItem? {
        guard let variable = eachVariable, let value = child.scope[variable], let frame = CanvasFrame(value) else { return nil }
        let keyField = container.property("key").plainText ?? "id"
        var key = child.entryKey ?? .null
        if case .record(let record) = value, let field = record[keyField] { key = field }
        var sizes: [CanvasSize] = []
        if case .record(let record) = value { sizes = CanvasSize.list(record["sizes"]) }
        return CanvasItem(key: key, frame: frame, sizes: sizes)
    }

    var items: [CanvasItem] { container.children.compactMap(item(for:)) }

    func entry(for child: ElementInstance) -> CanvasEntry? {
        guard let item = item(for: child) else { return nil }
        return CanvasEntry(key: item.key, enabled: enabled, scale: scale, coordinator: self)
    }

    func shownFrame(_ item: CanvasItem) -> CanvasFrame {
        live[item.key]?.frame ?? item.frame
    }

    func drag(_ key: Value, dx: Double, dy: Double, resize: Bool, ended: Bool) {
        guard enabled, let item = items.first(where: { $0.key == key }) else { return }
        let others = items.filter { $0.key != key }.map(\.frame)
        let geometry = self.geometry
        let frame: CanvasFrame
        if resize {
            frame = geometry.snapResize(item.frame, sizes: item.sizes, proposedWidth: item.frame.width + dx,
                                        proposedHeight: item.frame.height + dy, others: others)
        } else {
            frame = geometry.snapMove(CanvasFrame(x: item.frame.x + dx, y: item.frame.y + dy, width: item.frame.width, height: item.frame.height), others: others)
        }
        let valid = geometry.isValid(frame, sizes: item.sizes, others: others)
        live[key] = (frame, valid)
        mark(key, invalid: !valid)
        let event = Record([
            ("key", key), ("x", .number(frame.x)), ("y", .number(frame.y)),
            ("width", .number(frame.width)), ("height", .number(frame.height)),
            ("valid", .bool(valid)), ("phase", .string(ended ? "ended" : "changed")),
        ])
        let name = resize ? "on-resize" : "on-move"
        guard ended else {
            context?.fire(name, container, event)
            return
        }
        let round = (generation[key] ?? 0) + 1
        generation[key] = round
        let fired = context?.fire(name, container, event) { [weak self] task in
            Task { @MainActor [weak self] in
                await task?.value
                try? await Task.sleep(for: .milliseconds(60))
                self?.settle(key, round: round)
            }
        } ?? false
        if !fired { settle(key, round: round) }
    }

    func settle(_ key: Value, round: Int) {
        guard generation[key] == round else { return }
        mark(key, invalid: false)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { live[key] = nil }
    }

    private func mark(_ key: Value, invalid: Bool) {
        guard let child = container.children.first(where: { item(for: $0)?.key == key }) else { return }
        if invalid, !child.pseudo.contains(.invalid) { child.pseudo.insert(.invalid) }
        if !invalid, child.pseudo.contains(.invalid) { child.pseudo.remove(.invalid) }
    }
}

extension RenderContext {
    func canvas(for container: ElementInstance) -> CanvasCoordinator {
        let key = "canvas|" + container.identity.description
        if let existing = canvases[key], existing.container === container { return existing }
        let coordinator = CanvasCoordinator(container: container, context: self)
        canvases[key] = coordinator
        return coordinator
    }
}

struct CanvasElement: View {
    let element: ElementInstance
    let style: ComputedStyle
    let scope: RenderScope

    var body: some View {
        let coordinator = scope.context.canvas(for: element)
        let scale = coordinator.scale
        let children = element.children.filter { $0.kind != "flyout" }
        CanvasLayout(definite: Definite(style)) {
            ForEach(Array(children.enumerated()), id: \.element.identity) { index, child in
                if let item = coordinator.item(for: child) {
                    let frame = coordinator.shownFrame(item)
                    ElementView(element: child, scope: scope, position: ChildPosition(index: index, count: children.count),
                                canvasEntry: coordinator.entry(for: child))
                        .frame(width: frame.width, height: frame.height)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: frame.width * scale, height: frame.height * scale, alignment: .topLeading)
                        .layoutValue(key: CanvasOrigin.self, value: CGPoint(x: frame.x * scale, y: frame.y * scale))
                        .zIndex(coordinator.live[item.key] != nil ? 1 : 0)
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { coordinator.pageSize = $0 }
    }
}

struct CanvasOrigin: LayoutValueKey {
    static let defaultValue: CGPoint? = nil
}

struct CanvasLayout: Layout {
    var definite = Definite()

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var size = CGSize.zero
        for subview in subviews {
            let origin = subview[CanvasOrigin.self] ?? .zero
            let measured = subview.sizeThatFits(.unspecified)
            size.width = max(size.width, origin.x + measured.width)
            size.height = max(size.height, origin.y + measured.height)
        }
        return definite.apply(size, proposal)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let origin = subview[CanvasOrigin.self] ?? .zero
            let measured = subview.sizeThatFits(.unspecified)
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: ProposedViewSize(measured))
        }
    }
}

@MainActor
enum DragValues {
    private static var values: [String: Value] = [:]
    private static var counter = 0

    static func store(_ value: Value) -> String {
        counter += 1
        let token = "value-\(counter)"
        values = [token: value]
        return token
    }

    static func value(_ token: String) -> Value? { values[token] }
}
