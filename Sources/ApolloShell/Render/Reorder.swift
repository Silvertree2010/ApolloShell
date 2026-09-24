import SwiftUI
import AppKit
import Observation
import ApolloConfig
import ApolloStyle
import ApolloRuntime

struct ReorderEntry: Equatable {
    let token: String
    let key: Value
    let index: Int
    let app: String?
    let enabled: Bool
    weak var coordinator: ReorderCoordinator?

    static func == (a: ReorderEntry, b: ReorderEntry) -> Bool {
        a.token == b.token && a.index == b.index && a.enabled == b.enabled && a.app == b.app && a.coordinator === b.coordinator
    }
}

struct ReorderMove: Equatable {
    var from: Int
    var to: Int

    static func onto(from: Int, target: Int) -> ReorderMove {
        ReorderMove(from: from, to: from < target ? target + 1 : target)
    }

    func apply<T>(_ list: [T]) -> [T] {
        guard list.indices.contains(from), (0...list.count).contains(to), to != from, to != from + 1 else { return list }
        var copy = list
        let item = copy.remove(at: from)
        copy.insert(item, at: to > from ? to - 1 : to)
        return copy
    }
}

@MainActor
@Observable
final class ReorderCoordinator {
    let container: ElementInstance
    @ObservationIgnored weak var context: RenderContext?
    var preview: [Value]?
    @ObservationIgnored private var shownFor: [Value] = []
    @ObservationIgnored private(set) var dragging: Value?

    init(container: ElementInstance, context: RenderContext) {
        self.container = container
        self.context = context
    }

    var prefix: String { container.identity.description + "|" }

    var keys: [Value] { container.children.map { $0.entryKey ?? .null } }

    var enabled: Bool {
        let value = container.property("enabled")
        return value == .null || value.isTruthy
    }

    func entry(for child: ElementInstance, index: Int) -> ReorderEntry {
        let key = child.entryKey ?? .number(Double(index))
        var app: String?
        if case .string(let id) = key, id.contains(".") { app = id }
        return ReorderEntry(token: prefix + key.stringified, key: key, index: index, app: app, enabled: enabled, coordinator: self)
    }

    func ordered(_ children: [ElementInstance]) -> [ElementInstance] {
        let current = children.map { $0.entryKey ?? .null }
        guard let preview else { return children }
        if current != shownFor {
            self.preview = nil
            return children
        }
        return preview.compactMap { key in children.first { $0.entryKey == key } }
    }

    func begin(_ entry: ReorderEntry) {
        dragging = entry.key
    }

    func accepts(token: String, on target: ReorderEntry) -> Bool {
        token.hasPrefix(prefix) && enabled
    }

    func drop(token: String, on target: ReorderEntry) -> Bool {
        guard accepts(token: token, on: target) else { return false }
        let keys = self.keys
        guard let from = keys.firstIndex(where: { prefix + $0.stringified == token }) else { return false }
        return move(ReorderMove.onto(from: from, target: target.index), keys: keys)
    }

    @discardableResult
    func move(_ move: ReorderMove, keys: [Value]) -> Bool {
        dragging = nil
        guard move.apply(keys) != keys, let context else { return false }
        shownFor = keys
        preview = move.apply(keys)
        let targetIndex = move.to > move.from ? move.to - 1 : move.to
        let event = Record([
            ("from", .number(Double(move.from))), ("to", .number(Double(move.to))),
            ("key", keys[move.from]), ("from-key", keys[move.from]), ("to-key", keys[targetIndex]),
        ])
        context.fire("on-reorder", container, event)
        let task = context.pending.last
        Task { @MainActor [weak self] in
            await task?.value
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, self.preview != nil else { return }
            if self.keys == self.shownFor { self.preview = nil }
        }
        return true
    }

    func end(_ entry: ReorderEntry, droppedOutside: Bool) {
        dragging = nil
        guard droppedOutside, let context else { return }
        context.fire("on-drag-out", container, Record([("key", entry.key)]))
    }

    var accept: String? { container.property("accept").plainText }

    func acceptsForeign(_ pasteboard: NSPasteboard) -> Bool {
        guard let accept, pasteboard.string(forType: .apolloReorder) == nil else { return false }
        return EventFields.drop(pasteboard, accept: accept) != nil
    }

    func foreignDrop(_ pasteboard: NSPasteboard, on target: ReorderEntry) -> Bool {
        guard let accept, let context, var fields = EventFields.drop(pasteboard, accept: accept) else { return false }
        fields["index"] = .number(Double(target.index))
        return context.fire("on-drop", container, fields)
    }
}

extension RenderContext {
    func coordinator(for container: ElementInstance) -> ReorderCoordinator {
        let key = container.identity.description
        if let existing = reorders[key], existing.container === container { return existing }
        let coordinator = ReorderCoordinator(container: container, context: self)
        reorders[key] = coordinator
        return coordinator
    }
}

struct ReorderableElement: View {
    let element: ElementInstance
    let style: ComputedStyle
    let scope: RenderScope

    var body: some View {
        let coordinator = scope.context.coordinator(for: element)
        let children = coordinator.ordered(element.children)
        let axis = element.property("axis").plainText ?? "vertical"
        let content = ForEach(Array(children.enumerated()), id: \.element.identity) { index, child in
            ElementView(element: child, scope: scope, position: ChildPosition(index: index, count: children.count),
                        reorderEntry: coordinator.entry(for: child, index: index))
        }
        switch axis {
        case "horizontal":
            LayoutRenderers.flex(horizontal: true, style: style) { content }
        case "grid":
            LayoutRenderers.gridLayout(element, style) { content }
        default:
            LayoutRenderers.flex(horizontal: false, style: style) { content }
        }
    }
}
