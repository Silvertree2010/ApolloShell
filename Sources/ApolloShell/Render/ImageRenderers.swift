import SwiftUI
import AppKit
import ApolloConfig
import ApolloStyle
import ApolloRuntime

@MainActor
enum ImageRenderers {
    static func appIcon(_ element: ElementInstance, _ style: ComputedStyle, _ scope: RenderScope) -> AnyView {
        let app = element.arguments.first?.value ?? .null
        let badge = element.property("badge").plainText
        let subject = StyleResolver.subject(for: element)
        let color = scope.context.styles.color(fromCustom: "--badge-color", in: style, subject: subject, ancestors: Array(scope.ancestors.dropLast()))
        return AnyView(AppIconView(image: scope.context.icons.icon(for: app), badge: badge, badgeColor: color.map { StyleValues.color($0) } ?? .red))
    }
}

struct AppIconView: View {
    let image: NSImage?
    let badge: String?
    let badgeColor: Color

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Color.clear
            }
        }
        .overlay(alignment: .topTrailing) {
            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 15, minHeight: 15)
                    .background(badgeColor, in: .capsule)
                    .fixedSize()
                    .offset(x: 5, y: -3)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
    }
}
