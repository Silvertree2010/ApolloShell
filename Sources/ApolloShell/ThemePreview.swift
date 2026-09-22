import ApolloShellCore
import SwiftUI

/// A small, always identical scene of the shell painted with one theme:
/// desktop, the sidebar with its icons and clock, the launcher panel with a
/// highlighted row, an accent button and a toast. Every Marketplace theme
/// is shown this way, so the previews compare fairly and nobody uploads a
/// picture of their own.
///
/// Drawn in a fixed 320 x 200 grid and scaled to whatever size it gets.
struct ThemePreview: View {
    let theme: Theme
    let dark: Bool

    var body: some View {
        let style = ShellStyle(theme: theme, dark: dark)
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 320, proxy.size.height / 200)
            scene(style)
                .frame(width: 320, height: 200)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .aspectRatio(320 / 200, contentMode: .fit)
        .environment(\.colorScheme, dark ? .dark : .light)
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityLabel(Text("Preview of \(theme.title)"))
    }

    private func scene(_ style: ShellStyle) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(desktop(style))

            // Sidebar
            let barRadius = min(style.barRadius(0), 12)
            VStack(spacing: 7) {
                ForEach(0..<5) { index in
                    Circle()
                        .fill(index == 1 ? AnyShapeStyle(style.accent) : AnyShapeStyle(style.barIcon.opacity(0.85)))
                        .frame(width: 9, height: 9)
                }
                Spacer()
                Text("12:30")
                    .font(style.font(size: 6, weight: .semibold))
                    .foregroundStyle(style.barText)
            }
            .padding(.vertical, 10)
            .frame(width: 22, height: 200)
            .background(style.paintsBar ? style.barFill : AnyShapeStyle(.regularMaterial),
                        in: .rect(cornerRadius: barRadius))

            // Launcher panel
            let panelRadius = min(style.panelRadius(14), 22)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").font(.system(size: 7))
                    Text("Search").font(style.font(size: 7))
                    Spacer()
                }
                .foregroundStyle(style.secondaryText)
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(style.paintsSurface ? style.surfaceFill : AnyShapeStyle(.quaternary),
                            in: .rect(cornerRadius: min(style.controlRadius(6), 8)))

                ForEach(0..<4) { index in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill([style.accent, style.secondaryAccent, style.success, style.warning][index])
                            .frame(width: 11, height: 11)
                        Text(["Safari", "Terminal", "Notes", "Music"][index])
                            .font(style.font(size: 7, weight: index == 0 ? .semibold : .regular))
                            .foregroundStyle(style.text)
                        Spacer()
                    }
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background {
                        if index == 0 {
                            RoundedRectangle(cornerRadius: min(style.controlRadius(5), 8))
                                .fill(style.paintsLauncherHighlight ? style.launcherHighlightFill
                                                                    : AnyShapeStyle(style.launcherHighlight))
                        }
                    }
                }

                HStack {
                    Spacer()
                    Text("Open")
                        .font(style.font(size: 7, weight: .semibold))
                        .foregroundStyle(style.onAccent)
                        .padding(.horizontal, 10)
                        .frame(height: 15)
                        .background(style.accentFill, in: .capsule)
                }
            }
            .padding(8)
            .frame(width: 150)
            .background(style.paintsPanel ? style.panelFill : AnyShapeStyle(.regularMaterial),
                        in: .rect(cornerRadius: panelRadius))
            .offset(x: 44, y: 26)

            // Card
            VStack(alignment: .leading, spacing: 3) {
                Text("Weather").font(style.font(size: 6)).foregroundStyle(style.secondaryText)
                Text("18°").font(style.font(size: 14, weight: .semibold)).foregroundStyle(style.text)
                Capsule().fill(style.accent).frame(width: 60, height: 3)
            }
            .padding(8)
            .frame(width: 96, alignment: .leading)
            .background(style.paintsCard ? style.cardFill : AnyShapeStyle(.thinMaterial),
                        in: .rect(cornerRadius: min(style.cardRadius(10), 16)))
            .offset(x: 208, y: 26)

            // Toast
            HStack(spacing: 4) {
                Circle().fill(style.success).frame(width: 6, height: 6)
                Text("Theme applied").font(style.font(size: 6.5, weight: .medium))
            }
            .foregroundStyle(style.toastText)
            .padding(.horizontal, 8)
            .frame(height: 18)
            .background(style.paintsToast ? style.toastFill : AnyShapeStyle(.regularMaterial),
                        in: .rect(cornerRadius: min(style.toastRadius(9), 12)))
            .offset(x: 208, y: 160)
        }
    }

    /// The theme's background, or a quiet stand-in for the wallpaper.
    private func desktop(_ style: ShellStyle) -> AnyShapeStyle {
        if style.color(.background) != nil || style.value(ThemeGradientToken.background) != nil {
            return style.backgroundFill
        }
        return AnyShapeStyle(LinearGradient(
            colors: dark ? [Color(white: 0.16), Color(white: 0.08)] : [Color(white: 0.86), Color(white: 0.72)],
            startPoint: .top, endPoint: .bottom))
    }
}

extension Theme {
    /// A Marketplace theme read the same way as one from the folder.
    static func marketplace(_ theme: MarketTheme) -> Theme {
        Theme.make(identifier: theme.name, styleSheet: ThemeStyleSheetParser.parse(theme.css))
    }
}
