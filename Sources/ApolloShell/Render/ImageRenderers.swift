import SwiftUI
import AppKit
import ApolloConfig
import ApolloStyle
import ApolloRuntime

@MainActor
enum ImageRenderers {
    static func appIcon(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        let app = element.arguments.first?.value ?? .null
        return AnyView(AppIconView(image: scope.context.icons.icon(for: app), badge: element.property("badge").plainText,
                                   badgeStyle: BadgeStyle(style)))
    }
}

struct BadgeStyle {
    var color: Color
    var offset: CGSize
    var transition: AnyTransition
    var animation: Animation?

    init(_ style: ComputedStyle) {
        if case .color(let value)? = style["-apollo-badge-color"] {
            color = StyleValues.color(value)
        } else {
            color = StyleValues.systemColor("-apple-system-red")
        }
        if case .lengths(let list)? = style["-apollo-badge-offset"], list.count == 2 {
            offset = CGSize(width: list[0].value, height: list[1].value)
        } else {
            offset = .zero
        }
        (transition, animation) = StyleMotion.appear(style["-apollo-badge-appear"])
    }
}

struct AppIconView: View {
    let image: NSImage?
    let badge: String?
    let badgeStyle: BadgeStyle

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Color.clear
            }
        }
        .overlay(alignment: .topTrailing) {
            ZStack {
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(badgeStyle.color, in: .capsule)
                        .fixedSize()
                        .transition(badgeStyle.transition)
                }
            }
            .offset(badgeStyle.offset)
            .animation(badgeStyle.animation, value: badge)
        }
    }
}
