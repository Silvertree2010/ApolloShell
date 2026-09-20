import AppKit
import ApolloShellCore
import os
import SwiftUI

/// The root of the bar window: ONE piece of glass, and on it the bar and the
/// content of the status popout.
///
/// The glass is a single shape (`SidebarGlassShape`): the strip of the bar
/// plus the bulge of the open popout. Two separate pieces of glass side by
/// side take on different colors and show an edge at the seam; one shape has
/// the same color everywhere and no transition.
///
/// When it opens, the bulge grows out of the height of the symbol that was
/// clicked. The content stands still while it does and is uncovered by it
/// (Caelestia: ClipWrapper + Wrapper + Content).
struct SidebarRoot: View {
    let settings: ShellSettingsStore
    let context: BarModuleContext
    let popout: StatusPopoutModel
    /// The global edit mode; `nil` in previews and image samples.
    var editor: ShellEditor?
    /// The measured size of every content: that way the target size stands
    /// before the bulge sets off, and a content loaded later (Bluetooth only
    /// reads after the opening) glides to its new height.
    @State private var sizes: [StatusPopoutKind: CGSize] = [:]

    var body: some View {
        GeometryReader { geometry in
            let size = sizes[popout.shown] ?? CGSize(width: StatusPopoutContent.width(popout.shown), height: 200)
            let open = popout.isOpen
            let top = StatusPopoutPlacement.top(
                anchorY: popout.anchorY, height: size.height, containerHeight: geometry.size.height
            )
            // Closed: width 0 at the height of the symbol, so only the bar.
            let bulge = CGRect(
                x: Sidebar.width,
                y: open ? top : popout.anchorY - StatusPopoutLayout.seedHeight / 2,
                width: open ? size.width : 0,
                height: open ? size.height : StatusPopoutLayout.seedHeight
            )
            ZStack(alignment: .topLeading) {
                Color.clear
                    .modifier(SidebarGlass(shape: SidebarGlassShape(barWidth: Sidebar.width, bulge: bulge),
                                           background: settings.settings.bar.background))
                SidebarContent(settings: settings, context: context, editor: editor)
                    .frame(width: Sidebar.width)
                    .frame(maxHeight: .infinity)
                popoutContent(size: size, top: top, bulge: bulge, open: open)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .animation(StatusPopoutMotion.spatial, value: size)
            // The visible part of the bulge from the right bar edge on, for
            // the "outside" click test in `StatusPopout`.
            .onGeometryChange(for: CGRect.self) { _ in
                CGRect(x: 0, y: bulge.minY, width: bulge.width, height: bulge.height)
            } action: { popout.panelFrame = $0 }
        }
        // The popout model reaches the status capsule through the environment.
        .environment(popout)
    }

    /// All three contents are always built (only invisible): that way the size
    /// of the next one is measured before one switches. Visible is only what
    /// the bulge lets through.
    private func popoutContent(size: CGSize, top: CGFloat, bulge: CGRect, open: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(StatusPopoutKind.allCases, id: \.self) { kind in
                let active = open && popout.shown == kind
                StatusPopoutContent(model: popout, kind: kind)
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { sizes[kind] = $0 }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .offset(x: Sidebar.width, y: top)
                    .opacity(active ? 1 : 0)
                    .animation(active ? StatusPopoutMotion.fadeIn : StatusPopoutMotion.fadeOut, value: active)
                    .allowsHitTesting(active)
                    .accessibilityHidden(!active)
            }
        }
        .mask(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: StatusPopoutLayout.cornerRadius)
                .frame(width: bulge.width, height: bulge.height)
                .offset(x: bulge.minX, y: bulge.minY)
        }
    }
}

/// The background of the bar in its shape, replaced by a fixed area in image
/// samples (glass draws only white offscreen).
///
/// Which background is decided in Nexus > Bar > Background; why there is a
/// choice and what the entries are for stands at `BarBackground`.
private struct SidebarGlass<S: Shape>: ViewModifier {
    let shape: S
    let background: BarBackground
    @Environment(\.statusPopoutGlassStandIn) private var standIn
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellStyle) private var style

    /// The window color, half opaque: it pulls the glass towards the window
    /// color but lets it stay glass. A tint cannot stop the recoloring
    /// entirely anyway (see `BarBackground`) - `fixedGlass` is there for that.
    /// `fixedGlass` da.
    private static var tint: Color { Color(nsColor: .windowBackgroundColor).opacity(0.7) }

    /// With a theme, the theme colors the bar: the color (or the gradient) out
    /// of `--apollo-bar-color` or `--apollo-bar-gradient`, with
    /// `--apollo-bar-opacity`. The choice in Nexus > Bar stays visible below it
    /// as long as the theme lets light through and allows glass - otherwise a
    /// half-opaque bar would be a bar in front of the desktop.
    func body(content: Content) -> some View {
        if standIn {
            content.background(colorScheme == .dark ? Color(white: 0.17) : Color(white: 0.95), in: shape)
        } else if style.paintsBar {
            let opaque = style.barIsOpaque
            content
                .background(style.barFill, in: shape)
                .background {
                    if !opaque, style.glass {
                        Color.clear.glassEffect(.regular, in: shape)
                    }
                }
        } else {
            switch background {
            case .material:
                content.background(.regularMaterial, in: shape)
            case .glass:
                content.glassEffect(.regular, in: shape)
            case .tintedGlass:
                content.glassEffect(.regular.tint(Self.tint), in: shape)
            case .fixedGlass:
                // The order: the glass behind the content first, then the
                // opaque area behind the glass. The glass then has the same
                // area in front of it everywhere instead of the desktop and
                // the windows, so its adaptation has nothing left to adapt to.
                // `clear` instead of `regular`, because only that version does
                // not adapt at all according to Apple; the opaque area is the
                // layer `clear` needs for that.
                content
                    .glassEffect(.clear, in: shape)
                    .background(Color(nsColor: .windowBackgroundColor), in: shape)
            }
        }
    }
}

/// The outline of the bar including the bulge: one continuous path, not two
/// shapes laid over each other (SwiftUI fills those with a hole in the
/// overlap, depending on the rule).
///
/// At the transition to the bulge, two inward-curved corners, so that it
/// seems to grow out of the bar instead of looking glued on.
struct SidebarGlassShape: Shape {
    var barWidth: CGFloat
    var bulge: CGRect

    /// Animate the place and the size of the bulge: that way the shape glides
    /// on opening, switching and closing.
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(bulge.origin.x, bulge.origin.y),
                           AnimatablePair(bulge.size.width, bulge.size.height))
        }
        set {
            bulge = CGRect(x: newValue.first.first, y: newValue.first.second,
                           width: newValue.second.first, height: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard bulge.width > 0.5, bulge.height > 0.5 else {
            path.addRect(CGRect(x: rect.minX, y: rect.minY, width: barWidth, height: rect.height))
            return path
        }
        let r = min(StatusPopoutLayout.cornerRadius, bulge.width / 2, bulge.height / 2)
        let j = min(StatusPopoutLayout.join, bulge.width, max(0, (rect.height - bulge.height) / 2))
        let x = rect.minX
        let edge = x + barWidth
        let top = max(rect.minY, bulge.minY)
        let bottom = min(rect.maxY, bulge.maxY)
        let right = edge + bulge.width

        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: edge, y: rect.minY))
        // Down the right bar edge to the bulge, then curved inwards into it.
        //
        path.addLine(to: CGPoint(x: edge, y: top - j))
        path.addQuadCurve(to: CGPoint(x: edge + j, y: top),
                          control: CGPoint(x: edge, y: top))
        path.addLine(to: CGPoint(x: right - r, y: top))
        path.addQuadCurve(to: CGPoint(x: right, y: top + r), control: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right, y: bottom - r))
        path.addQuadCurve(to: CGPoint(x: right - r, y: bottom), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: edge + j, y: bottom))
        path.addQuadCurve(to: CGPoint(x: edge, y: bottom + j), control: CGPoint(x: edge, y: bottom))
        // On down the bar edge and around the bar back again.
        path.addLine(to: CGPoint(x: edge, y: rect.maxY))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
