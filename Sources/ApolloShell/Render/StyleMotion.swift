import SwiftUI
import ApolloStyle

enum StyleMotion {
    static func animation(_ curve: TimingCurve, duration: Double) -> Animation {
        switch curve {
        case .linear:
            .linear(duration: duration)
        case let .cubicBezier(a, b, c, d):
            .timingCurve(a, b, c, d, duration: duration)
        case let .spring(response, damping):
            .spring(response: response, dampingFraction: damping)
        }
    }

    static func transition(_ style: ComputedStyle, _ property: String) -> Animation? {
        guard case .transitions(let list)? = style["transition"] else { return nil }
        let match = list.last { $0.property == property } ?? (property == "match" ? nil : list.last { $0.property == "all" })
        guard let match, match.duration > 0 else { return nil }
        return animation(match.curve, duration: match.duration)
    }

    static func valueAnimation(_ style: ComputedStyle) -> Animation? {
        transition(style, "value")
    }

    static func appear(_ value: CSSValue?) -> (transition: AnyTransition, animation: Animation?) {
        guard case .appear(let list)? = value, let first = list.first else { return (.identity, nil) }
        var transition = AnyTransition.identity
        for effect in first.effects {
            transition = transition.combined(with: self.transition(effect))
        }
        return (transition, first.duration > 0 ? animation(first.curve, duration: first.duration) : nil)
    }

    static func transition(_ effect: AppearEffect) -> AnyTransition {
        switch effect {
        case .fade:
            .opacity
        case .scale(let factor):
            .scale(scale: factor)
        case let .slide(edge, distance):
            if let distance {
                .offset(slideOffset(edge, distance))
            } else {
                .move(edge: slideEdge(edge))
            }
        case .blur(let radius):
            .modifier(active: BlurEffect(radius: radius), identity: BlurEffect(radius: 0))
        }
    }

    static func slideEdge(_ edge: String) -> Edge {
        switch edge {
        case "top": .top
        case "bottom": .bottom
        case "trailing": .trailing
        default: .leading
        }
    }

    static func slideOffset(_ edge: String, _ distance: Double) -> CGSize {
        switch edge {
        case "top": CGSize(width: 0, height: -distance)
        case "bottom": CGSize(width: 0, height: distance)
        case "trailing": CGSize(width: distance, height: 0)
        default: CGSize(width: -distance, height: 0)
        }
    }
}

struct BlurEffect: ViewModifier {
    let radius: Double

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}
