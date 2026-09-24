import SwiftUI
import AppKit
import ApolloShellCore
import ApolloConfig
import ApolloStyle
import ApolloRuntime

@MainActor
enum InputRenderers {
    static func toggle(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        AnyView(ToggleElement(element: element, style: style, context: scope.context))
    }

    static func slider(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        AnyView(SliderElement(element: element, style: style, scope: scope))
    }

    static func input(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        AnyView(InputElement(element: element, style: style, context: scope.context))
    }

    static func keyRecorder(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        AnyView(KeyRecorderElement(element: element, style: style, context: scope.context))
    }
}

struct PassiveZone: View {
    let element: ElementInstance
    let context: RenderContext

    var body: some View {
        MouseCatcher(element: element, context: context, config: { var config = MouseConfig(); config.passive = true; return config }())
    }
}

struct AccentTint: ViewModifier {
    let style: ComputedStyle

    func body(content: Content) -> some View {
        if case .color(let color)? = style["accent-color"] {
            content.tint(StyleValues.color(color))
        } else {
            content
        }
    }
}

struct ToggleElement: View {
    let element: ElementInstance
    let style: ComputedStyle
    let context: RenderContext

    var body: some View {
        let checked = element.property("checked").isTruthy
        Toggle("", isOn: Binding(get: { checked }, set: { value in
            context.fire("on-change", element, Record([("value", .bool(value))]))
        }))
        .toggleStyle(.switch)
        .labelsHidden()
        .modifier(AccentTint(style: style))
        .disabled(element.property("disabled").isTruthy)
        .overlay { PassiveZone(element: element, context: context) }
    }
}

struct SliderMetrics: Equatable {
    var min: Double
    var max: Double
    var step: Double

    init(min: Double, max: Double, step: Double) {
        self.min = min
        self.max = max > min ? max : min + 1
        self.step = step
    }

    @MainActor
    init(_ element: ElementInstance) {
        self.init(min: StyleValues.numberValue(element.property("min")) ?? 0,
                  max: StyleValues.numberValue(element.property("max")) ?? 1,
                  step: StyleValues.numberValue(element.property("step")) ?? 0)
    }

    func fraction(_ value: Double) -> Double {
        Swift.min(1, Swift.max(0, (value - min) / (max - min)))
    }

    func value(fraction: Double) -> Double {
        snap(min + Swift.min(1, Swift.max(0, fraction)) * (max - min))
    }

    func snap(_ value: Double) -> Double {
        let clamped = Swift.min(max, Swift.max(min, value))
        guard step > 0 else { return clamped }
        return Swift.min(max, min + ((clamped - min) / step).rounded() * step)
    }
}

struct SliderElement: View {
    let element: ElementInstance
    let style: ComputedStyle
    let scope: RenderScope
    @State private var dragValue: Double?

    var body: some View {
        let metrics = SliderMetrics(element)
        let bound = StyleValues.numberValue(element.property("value")) ?? metrics.min
        let shown = dragValue ?? bound
        let vertical = element.property("vertical").isTruthy
        let thumb = thumbSize
        let keyStep = StyleValues.numberValue(element.property("key-step")) ?? (metrics.step > 0 ? metrics.step : (metrics.max - metrics.min) / 20)
        GeometryReader { proxy in
            let length = vertical ? proxy.size.height : proxy.size.width
            let extent = vertical ? thumb.height : thumb.width
            let travel = Swift.max(0, length - extent)
            let center = extent / 2 + metrics.fraction(shown) * travel
            ZStack(alignment: vertical ? .bottom : .leading) {
                Capsule().fill(trackColor)
                BackgroundLayers(style: ComputedStyle(values: ["background": fillLayers]), shape: AnyShape(Capsule()), context: scope.context)
                    .frame(width: vertical ? nil : Swift.max(extent > 0 ? center : 0, metrics.fraction(shown) * length),
                           height: vertical ? Swift.max(extent > 0 ? center : 0, metrics.fraction(shown) * length) : nil)
                if extent > 0 {
                    thumbView(thumb)
                        .offset(x: vertical ? 0 : center - thumb.width / 2, y: vertical ? -(center - thumb.height / 2) : 0)
                        .frame(maxWidth: vertical ? .infinity : nil, maxHeight: vertical ? nil : .infinity)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard !element.property("disabled").isTruthy else { return }
                let position = vertical ? length - drag.location.y : drag.location.x
                let value = metrics.value(fraction: travel > 0 ? (position - extent / 2) / travel : 0)
                if value != dragValue {
                    dragValue = value
                    scope.context.fire("on-change", element, Record([("value", .number(value))]))
                }
            }.onEnded { _ in
                if let value = dragValue { scope.context.fire("on-commit", element, Record([("value", .number(value))])) }
                dragValue = nil
            })
        }
        .frame(minWidth: vertical ? thumb.width : 20, minHeight: vertical ? 20 : Swift.max(thumb.height, 4))
        .overlay { PassiveZone(element: element, context: scope.context) }
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((metrics.fraction(shown) * 100).rounded())) %"))
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? keyStep : -keyStep
            let value = metrics.snap(bound + delta)
            scope.context.fire("on-change", element, Record([("value", .number(value))]))
            scope.context.fire("on-commit", element, Record([("value", .number(value))]))
        }
    }

    var thumbSize: CGSize {
        if case .lengths(let list)? = style["-apollo-thumb-size"], list.count == 2 {
            return CGSize(width: list[0].value, height: list[1].value)
        }
        return .zero
    }

    var trackColor: Color {
        if case .color(let color)? = style["-apollo-track-color"] { return StyleValues.color(color) }
        return Color.primary.opacity(0.15)
    }

    var fillLayers: CSSValue {
        if case .layers(let list)? = style["-apollo-fill-color"] { return .layers(list) }
        return .layers([.color(.system(name: "-apple-system-control-accent", alpha: 1))])
    }

    @ViewBuilder
    func thumbView(_ size: CGSize) -> some View {
        let color: Color = {
            if case .color(let value)? = style["-apollo-thumb-color"] { return StyleValues.color(value) }
            return .white
        }()
        let shadows: CSSValue? = style["-apollo-thumb-shadow"]
        ZStack {
            Capsule().fill(color)
                .modifier(BoxShadows(shadows, shape: AnyShape(Capsule())))
            ElementChildren(children: element.slotChildren["thumb"] ?? [], scope: scope)
        }
        .frame(width: size.width, height: size.height)
    }
}

enum KeyMatch {
    static func modifiers(_ flags: NSEvent.ModifierFlags) -> HotKeyModifiers {
        var result: HotKeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.control) { result.insert(.control) }
        return result
    }

    static func matches(_ chord: KeyChord, keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        UInt32(keyCode) == chord.keyCode && modifiers(flags) == chord.modifiers
    }
}

@MainActor
final class VarWatcher {
    private var cancel: (@MainActor () -> Void)?

    func start(_ cancel: (@MainActor () -> Void)?) {
        stop()
        self.cancel = cancel
    }

    func stop() {
        cancel?()
        cancel = nil
    }
}

@MainActor
final class KeyInterceptor {
    private var monitor: Any?

    func start(_ handle: @escaping @MainActor (NSEvent) -> Bool) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            nonisolated(unsafe) let captured = event
            let consumed = MainActor.assumeIsolated { handle(captured) }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

struct InputElement: View {
    let element: ElementInstance
    let style: ComputedStyle
    let context: RenderContext
    @State private var text = ""
    @State private var interceptor = KeyInterceptor()
    @State private var watcher = VarWatcher()
    @FocusState private var focused: Bool

    var bindName: String? {
        guard let bind = element.property("bind").plainText, bind.hasPrefix("var.") else { return nil }
        return String(bind.dropFirst(4))
    }

    var external: String {
        if let name = bindName, let runtime = context.runtime { return runtime.variable(name).stringified }
        return element.property("value").stringified
    }

    var body: some View {
        let textStyle = TextStyle(style)
        let placeholder = element.property("placeholder").plainText ?? ""
        let binding = Binding(get: { text }, set: { value in
            guard value != text else { return }
            text = value
            if let name = bindName { context.runtime?.setVariable(name, .string(value)) }
            context.fire("on-change", element, Record([("value", .string(value))]))
        })
        Group {
            if element.property("secure").isTruthy {
                SecureField(placeholder, text: binding)
            } else {
                TextField(placeholder, text: binding)
            }
        }
        .textFieldStyle(.plain)
        .font(textStyle.font)
        .foregroundStyle(textStyle.color)
        .multilineTextAlignment(textStyle.alignment)
        .focused($focused)
        .disabled(element.property("disabled").isTruthy)
        .onSubmit { context.fire("on-submit", element, Record([("value", .string(text))])) }
        .onAppear {
            text = external
            if element.property("focus").isTruthy { focused = true }
            if let name = bindName, let runtime = context.runtime {
                let text = $text
                watcher.start(runtime.watch(name) { [weak runtime] in
                    guard let value = runtime?.variable(name).stringified, value != text.wrappedValue else { return }
                    text.wrappedValue = value
                })
            }
        }
        .onChange(of: external) { _, value in if value != text { text = value } }
        .onChange(of: element.property("focus").isTruthy) { _, value in if value { focused = true } }
        .onChange(of: focused) { _, value in
            if value { element.pseudo.insert(.focus) } else { element.pseudo.remove(.focus) }
            if value, !element.ir.keyHandlers.isEmpty {
                interceptor.start { event in intercept(event) }
            } else {
                interceptor.stop()
            }
        }
        .onDisappear {
            interceptor.stop()
            watcher.stop()
        }
        .overlay { PassiveZone(element: element, context: context) }
    }

    func intercept(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        for (index, handler) in element.ir.keyHandlers.enumerated() {
            guard let chord = KeyChord.parse(handler.chord), KeyMatch.matches(chord, keyCode: event.keyCode, flags: event.modifierFlags) else { continue }
            if let task = context.runtime?.run(handler.actions, on: element.identity, site: "key#\(index)", event: Record([("chord", .string(chord.canonical))]), locals: [:]) {
                context.track(task)
            }
            return true
        }
        return false
    }
}

struct RecorderOutcome: Equatable {
    enum Kind: Equatable { case cancel, record(String), rejected(String) }
    var kind: Kind
    var warning: String?
    var conflict: String?

    @MainActor static func evaluate(keyCode: UInt32, modifiers: HotKeyModifiers, reject: [String], current: String?, binds: [(id: String, chord: String)],
                         keyName: @MainActor (UInt32) -> String? = { _ in nil }) -> RecorderOutcome {
        switch HotKeyRecording.evaluate(keyCode: keyCode, modifiers: modifiers) {
        case .cancel:
            return RecorderOutcome(kind: .cancel)
        case .clear:
            return RecorderOutcome(kind: .record(""))
        case .rejected(let reason):
            return RecorderOutcome(kind: .rejected(HotKeyText.rejection(reason)))
        case .record(let hotKey):
            guard let chord = KeyChord(hotKey: hotKey) else { return RecorderOutcome(kind: .cancel) }
            let canonical = chord.canonical
            let normalized = reject.compactMap { KeyChord.parse($0)?.canonical }
            if normalized.contains(canonical) {
                return RecorderOutcome(kind: .rejected("Already assigned to \(KeyboardLayout.label(chord, keyName: keyName))"))
            }
            let own = current.flatMap(KeyChord.parse)?.canonical
            let conflict = binds.first { KeyChord.parse($0.chord)?.canonical == canonical && canonical != own }?.id
            return RecorderOutcome(kind: .record(canonical), warning: HotKeyAdvice.warning(for: hotKey).map(HotKeyText.warning), conflict: conflict)
        }
    }
}

struct StopWhenHidden: ViewModifier {
    let action: @MainActor () -> Void
    @Environment(\.surfaceShown) private var shown

    func body(content: Content) -> some View {
        content.onChange(of: shown) { _, visible in
            if !visible { action() }
        }
    }
}

struct KeyRecorderElement: View {
    let element: ElementInstance
    let style: ComputedStyle
    let context: RenderContext
    @State private var recording = false
    @State private var live: HotKeyModifiers = []
    @State private var message: String?
    @State private var interceptor = KeyInterceptor()

    var body: some View {
        let textStyle = TextStyle(style)
        let value = element.property("value").plainText
        let shown: String = {
            if recording { return live.isEmpty ? "…" : live.symbols }
            if let value, let chord = KeyChord.parse(value) { return KeyboardLayout.label(chord, keyName: context.keyName) }
            return element.property("placeholder").plainText ?? ""
        }()
        VStack(alignment: .leading, spacing: 2) {
            Text(shown)
                .font(textStyle.font)
                .foregroundStyle(textStyle.color)
            if let message {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { recording ? stop() : start() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
        .onDisappear { stop() }
        .modifier(StopWhenHidden { stop() })
        .overlay { PassiveZone(element: element, context: context) }
        .accessibilityAddTraits(.isButton)
    }

    func start() {
        recording = true
        message = nil
        live = []
        element.pseudo.insert(.active)
        context.onRecording(true)
        interceptor.start { event in handle(event) }
    }

    func stop() {
        guard recording else { return }
        recording = false
        live = []
        element.pseudo.remove(.active)
        interceptor.stop()
        context.onRecording(false)
    }

    func handle(_ event: NSEvent) -> Bool {
        let modifiers = KeyMatch.modifiers(event.modifierFlags)
        if event.type == .flagsChanged {
            live = modifiers
            return true
        }
        let reject: [String] = {
            if case .list(let list) = element.property("reject") { return list.compactMap(\.plainText) }
            return element.property("reject").plainText.map { [$0] } ?? []
        }()
        let outcome = RecorderOutcome.evaluate(keyCode: UInt32(event.keyCode), modifiers: modifiers, reject: reject,
                                               current: element.property("value").plainText, binds: context.runtime?.bindChords() ?? [], keyName: context.keyName)
        switch outcome.kind {
        case .cancel:
            stop()
        case .rejected(let text):
            message = text
        case .record(let chord):
            message = nil
            context.fire("on-change", element, Record([
                ("chord", .string(chord)),
                ("warning", outcome.warning.map { .string($0) } ?? .null),
                ("conflict", outcome.conflict.map { .string($0) } ?? .null),
            ]))
            stop()
        }
        return true
    }
}
