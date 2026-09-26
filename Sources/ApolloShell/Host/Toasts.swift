import Foundation
import ApolloBase
import ApolloConfig
import ApolloRuntime

@MainActor
final class ToastCenter {
    struct Entry: Equatable {
        var id: String
        var title: Value
        var body: Value
        var icon: Value
        var kind: String
        var expires: Date
        var queued: Bool
    }

    struct Stack {
        var surfaceID: String
        var screenKey: String
        var entries: [Entry] = []
        var tick: DispatchWorkItem?
        var closing: DispatchWorkItem?
    }

    static let defaultDuration: TimeInterval = 5
    static let defaultMax = 4
    static let closeDelay: TimeInterval = 0.5
    static let tickInterval: TimeInterval = 1

    weak var runtime: ShellRuntime?
    var targetScreen: @MainActor () -> String? = { nil }
    var now: @MainActor () -> Date = { Date() }
    var schedule: @MainActor (TimeInterval, DispatchWorkItem) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private(set) var stacks: [String: Stack] = [:]
    private var counter = 0

    @discardableResult
    func post(style: String, fields: Record, duration: TimeInterval?, screenKey: String? = nil) -> String? {
        guard let runtime, let screen = screenKey ?? targetScreen(), let surface = runtime.surface(style, screenKey: screen), surface.ir.kind == "toast" else { return nil }
        counter += 1
        let key = style + "@" + screen
        var stack = stacks[key] ?? Stack(surfaceID: style, screenKey: screen)
        let limit = Self.limit(surface)
        let alive = stack.entries.filter { $0.expires > now() }
        let seconds = duration ?? SurfaceWindowSpec.seconds(surface.property("duration")) ?? Self.defaultDuration
        let kind: String = if case .string(let text)? = fields["kind"], !text.isEmpty { text } else { "info" }
        stack.entries.append(Entry(id: "toast-\(counter)", title: fields["title"] ?? .null, body: fields["body"] ?? .null, icon: fields["icon"] ?? .null, kind: kind, expires: now().addingTimeInterval(seconds), queued: alive.count >= limit))
        stacks[key] = stack
        refresh(key)
        return "toast-\(counter)"
    }

    func dismiss(_ id: String, surfaceID: String, screenKey: String) {
        let key = surfaceID + "@" + screenKey
        guard var stack = stacks[key] else { return }
        stack.entries.removeAll { $0.id == id }
        stacks[key] = stack
        refresh(key)
    }

    func stop() {
        for stack in stacks.values {
            stack.tick?.cancel()
            stack.closing?.cancel()
        }
        stacks.removeAll()
    }

    func refresh(_ key: String) {
        guard var stack = stacks[key], let runtime else { return }
        stack.tick?.cancel()
        stack.tick = nil
        let current = now()
        stack.entries.removeAll { $0.expires <= current }
        guard let surface = runtime.surface(stack.surfaceID, screenKey: stack.screenKey), surface.ir.kind == "toast" else {
            stack.closing?.cancel()
            stacks[key] = nil
            return
        }
        let visible = Array(stack.entries.prefix(Self.limit(surface)))
        let ordered = surface.property("newest") == .string("first") ? visible.reversed() : visible
        runtime.setToasts(stack.surfaceID, screenKey: stack.screenKey, ordered.map { Self.record($0, now: current) })
        if stack.entries.isEmpty {
            if stack.closing == nil, surface.isOpen {
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated { self?.finishClosing(key) }
                }
                stack.closing = work
                schedule(Self.closeDelay, work)
            }
        } else {
            stack.closing?.cancel()
            stack.closing = nil
            if !surface.isOpen { runtime.open(stack.surfaceID, screenKey: stack.screenKey) }
            let soonest = stack.entries.map { $0.expires.timeIntervalSince(current) }.min() ?? Self.tickInterval
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.refresh(key) }
            }
            stack.tick = work
            schedule(max(0, min(soonest, Self.tickInterval)), work)
        }
        stacks[key] = stack
    }

    private func finishClosing(_ key: String) {
        guard let stack = stacks[key], stack.entries.isEmpty else { return }
        stacks[key] = nil
        runtime?.close(stack.surfaceID, screenKey: stack.screenKey)
    }

    static func limit(_ surface: SurfaceInstance) -> Int {
        guard case .number(let number) = surface.property("max"), number.isFinite, number >= 1 else { return defaultMax }
        return Int(min(number, 1_000_000))
    }

    static func record(_ entry: Entry, now: Date) -> Value {
        .record(Record([
            ("id", .string(entry.id)),
            ("title", entry.title),
            ("body", entry.body),
            ("icon", entry.icon),
            ("kind", .string(entry.kind)),
            ("remaining", .number(max(0, entry.expires.timeIntervalSince(now)).rounded(.up))),
            ("queued", .bool(entry.queued)),
        ]))
    }
}

@MainActor
final class NotifyAction: ActionImplementation {
    let center: ToastCenter

    init(center: ToastCenter) {
        self.center = center
    }

    func perform(_ call: ResolvedActionCall, environment: ActionEnvironment, runtime: any ActionRuntime) async throws {
        let style: String = if case .string(let text)? = call.properties["style"], !text.isEmpty { text } else { "default" }
        let duration = call.properties["duration"].flatMap(SurfaceWindowSpec.seconds)
        if center.post(style: style, fields: call.properties, duration: duration) == nil {
            runtime.warn(Diagnostic(.warning, "notify shows nothing: there is no toast \"\(style)\"", span: call.span))
        }
    }
}

@MainActor
final class ToastDismissAction: ActionImplementation {
    let center: ToastCenter

    init(center: ToastCenter) {
        self.center = center
    }

    func perform(_ call: ResolvedActionCall, environment: ActionEnvironment, runtime: any ActionRuntime) async throws {
        guard case .record(let toast)? = environment.scope["toast"], case .string(let id)? = toast["id"], let surfaceID = environment.surfaceID, let screenKey = environment.screenKey else {
            throw ActionFailure("toast.dismiss works only inside a toast")
        }
        center.dismiss(id, surfaceID: surfaceID, screenKey: screenKey)
    }
}
