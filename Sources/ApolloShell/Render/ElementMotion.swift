import SwiftUI
import ApolloStyle
import ApolloRuntime

struct Motion: ViewModifier {
    let element: ElementInstance
    let style: ComputedStyle
    let context: RenderContext
    var dynamicInline = false
    @Environment(\.matchNamespace) private var namespace
    @Environment(\.renderMode) private var renderMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let plan = MotionPlan(style, reduceMotion: reduceMotion)
        content
            .modifier(RunningAnimation(spec: renderMode ? nil : plan.animation, enabled: dynamicInline || context.styles.declared.contains("animation")))
            .modifier(ChangeAnimation(animation: plan.change, style: style))
            .modifier(Matched(id: element.property("match-id").plainText, fallback: element.identity.description,
                              enabled: element.ir.properties["match-id"] != nil, namespace: namespace))
            .transition(plan.transition)
    }
}

struct MotionPlan {
    var change: Animation?
    var transition: AnyTransition
    var animation: AnimationSpec?

    init(_ style: ComputedStyle, reduceMotion: Bool = false) {
        change = Self.changeAnimation(style)
        let appear = StyleMotion.appear(style["-apollo-appear"])
        let disappear = StyleMotion.appear(style["-apollo-disappear"])
        var insertion = appear.transition
        var removal = disappear.transition
        if reduceMotion {
            insertion = appear.animation == nil ? .identity : .opacity
            removal = disappear.animation == nil ? .identity : .opacity
        }
        if let animation = appear.animation { insertion = insertion.animation(animation) }
        if let animation = disappear.animation { removal = removal.animation(animation) }
        if let match = StyleMotion.transition(style, "match"), appear.animation == nil {
            insertion = AnyTransition.opacity.animation(match)
            removal = AnyTransition.opacity.animation(match)
        }
        transition = .asymmetric(insertion: insertion, removal: removal)
        animation = AnimationSpec(style, reduceMotion: reduceMotion)
    }

    static let ownProperties: Set<String> = ["value", "content", "match", "size"]

    static func changeAnimation(_ style: ComputedStyle) -> Animation? {
        guard case .transitions(let list)? = style["transition"] else { return nil }
        let candidates = list.filter { !ownProperties.contains($0.property) && $0.duration > 0 }
        guard let longest = candidates.max(by: { $0.duration < $1.duration }) else { return nil }
        return StyleMotion.animation(longest.curve, duration: longest.duration)
    }
}

struct AnimationSpec: Equatable {
    enum Kind: String {
        case spin, pulse, wiggle, bounce
    }

    var kind: Kind
    var duration: Double
    var count: Double?
    var delay: Double

    init?(_ style: ComputedStyle, reduceMotion: Bool = false) {
        guard case let .animation(name, duration, count)? = style["animation"], let kind = Kind(rawValue: name), duration > 0 else { return nil }
        if reduceMotion, kind != .pulse { return nil }
        self.kind = kind
        self.duration = duration
        self.count = count
        if case .duration(let delay)? = style["animation-delay"] { self.delay = delay } else { self.delay = 0 }
    }

    func progress(elapsed: Double) -> Double? {
        let t = (elapsed - delay) / duration
        if t < 0 { return 0 }
        if let count, t >= count { return nil }
        return t - t.rounded(.down)
    }

    struct Pose: Equatable {
        var rotation: Double = 0
        var opacity: Double = 1
        var offsetY: Double = 0
    }

    func pose(_ phase: Double?) -> Pose {
        guard let phase else { return Pose() }
        switch kind {
        case .spin:
            return Pose(rotation: phase * 360)
        case .pulse:
            return Pose(opacity: 1 - 0.6 * (0.5 - 0.5 * cos(phase * 2 * .pi)))
        case .wiggle:
            return Pose(rotation: sin(phase * 2 * .pi) * 0.6)
        case .bounce:
            if phase < 0.5 {
                let u = phase / 0.5
                return Pose(offsetY: -10 * (1 - (1 - u) * (1 - u)))
            }
            let u = (phase - 0.5) / 0.5
            return Pose(offsetY: -10 * (1 - u * u))
        }
    }
}

struct RunningAnimation: ViewModifier {
    let spec: AnimationSpec?
    var enabled = true
    @State private var start = Date()
    @State private var finished = false

    func body(content: Content) -> some View {
        if enabled {
            TimelineView(.animation(paused: spec == nil || finished)) { timeline in
                let pose = spec.map { $0.pose($0.progress(elapsed: timeline.date.timeIntervalSince(start))) } ?? AnimationSpec.Pose()
                content
                    .rotationEffect(.degrees(pose.rotation))
                    .opacity(pose.opacity)
                    .offset(y: pose.offsetY)
            }
            .task(id: spec) {
                await Self.run(spec, restart: {
                    start = Date()
                    finished = false
                }, finish: { finished = true })
            }
        } else {
            content
        }
    }

    static func run(_ spec: AnimationSpec?, restart: () -> Void, finish: () -> Void) async {
        guard let spec else { return }
        restart()
        guard let count = spec.count else { return }
        try? await Task.sleep(for: .seconds(max(0, spec.delay + spec.duration * count)))
        if !Task.isCancelled { finish() }
    }
}

struct ChangeAnimation: ViewModifier {
    let animation: Animation?
    let style: ComputedStyle

    func body(content: Content) -> some View {
        content.transaction(value: style) { transaction in
            if let animation { transaction.animation = animation }
        }
    }
}

struct Matched: ViewModifier {
    let id: String?
    let fallback: String
    let enabled: Bool
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if enabled, let namespace {
            content.matchedGeometryEffect(id: id ?? "unmatched:" + fallback, in: namespace)
        } else {
            content
        }
    }
}

private struct MatchNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var matchNamespace: Namespace.ID? {
        get { self[MatchNamespaceKey.self] }
        set { self[MatchNamespaceKey.self] = newValue }
    }
}
