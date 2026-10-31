import AppKit
import ApolloShellCore
import os
import SwiftUI

/// Wurzel des Leistenfensters: EIN Glas, darauf die Leiste und der Inhalt
/// des Statuspopouts.
///
/// Das Glas ist eine einzige Form (`SidebarGlassShape`): der Streifen der
/// Leiste plus die Beule des offenen Popouts. Zwei getrennte Glaeser
/// nebeneinander faerben sich verschieden ein und zeigen an der Naht eine
/// Kante; eine Form hat ueberall dieselbe Farbe und keinen Uebergang.
///
/// Beim Oeffnen waechst die Beule aus der Hoehe des angeklickten Symbols
/// heraus. Der Inhalt steht dabei still und wird von ihr aufgedeckt
/// (Caelestia: ClipWrapper + Wrapper + Content).
struct SidebarRoot: View {
    let settings: ShellSettingsStore
    let context: BarModuleContext
    let popout: StatusPopoutModel
    let edges: SidebarEdges
    /// Gemessene Groesse jedes Inhalts: so steht die Zielgroesse schon fest,
    /// bevor die Beule losgeht, und ein spaeter geladener Inhalt (Bluetooth
    /// liest erst nach dem Oeffnen) gleitet auf seine neue Hoehe.
    @State private var sizes: [StatusPopoutKind: CGSize] = [:]
    @Environment(\.shellStyle) private var style

    var body: some View {
        GeometryReader { geometry in
            let full = sizes[popout.shown] ?? CGSize(width: StatusPopoutContent.width(popout.shown), height: 200)
            let open = popout.isOpen
            let lead = edges.left
            let h = max(0, geometry.size.height - edges.bottom)
            let size = CGSize(width: full.width, height: h > 0 ? min(full.height, h) : full.height)
            let top = StatusPopoutPlacement.top(
                anchorY: popout.anchorY, height: size.height, containerHeight: h
            )
            // Geschlossen: Breite 0 auf Hoehe des Symbols, also nur Leiste.
            let bulge = CGRect(
                x: lead + Sidebar.width,
                y: open ? top : popout.anchorY - StatusPopoutLayout.seedHeight / 2,
                width: open ? size.width : 0,
                height: open ? size.height : StatusPopoutLayout.seedHeight
            )
            // Rechts: dieselbe Buehne, an der Mitte des Fensters gespiegelt.
            let right = edges.side == .right
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                Color.clear
                    .modifier(SidebarGlass(shape: SidebarGlassShape(barWidth: lead + Sidebar.width, bulge: bulge,
                                                                    mirrored: right,
                                                                    radius: style.barRadius(0), inset: edges.bottom)))
                SidebarContent(settings: settings, context: context)
                    .frame(width: Sidebar.width, height: h)
                    .offset(x: right ? width - lead - Sidebar.width : lead)
                popoutContent(size: size, top: top, bulge: bulge, open: open,
                              x: right ? width - bulge.maxX : bulge.minX)
            }
            .environment(\.barSide, edges.side)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .animation(StatusPopoutMotion.spatial, value: size)
            // Sichtbarer Teil der Beule ab der rechten Leistenkante, fuer den
            // Klicktest "ausserhalb" in `StatusPopout`.
            .onGeometryChange(for: CGRect.self) { _ in
                CGRect(x: 0, y: bulge.minY, width: bulge.width, height: bulge.height)
            } action: { popout.panelFrame = $0 }
        }
        // Das Popout-Modell kommt ueber die Umgebung zur Statuskapsel.
        .environment(popout)
    }

    /// Alle drei Inhalte sind immer aufgebaut (nur unsichtbar): so ist die
    /// Groesse des naechsten schon gemessen, bevor man wechselt. Sichtbar ist
    /// nur, was die Beule freigibt.
    /// `x`: linke Kante der Beule im Fenster (rechts gespiegelt).
    private func popoutContent(size: CGSize, top: CGFloat, bulge: CGRect, open: Bool, x: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(StatusPopoutKind.allCases, id: \.self) { kind in
                let active = open && popout.shown == kind
                ScrollView(.vertical) {
                    StatusPopoutContent(model: popout, kind: kind)
                        .fixedSize()
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { sizes[kind] = $0 }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollDisabled((sizes[kind]?.height ?? 0) <= size.height)
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .offset(x: x, y: top)
                .opacity(active ? 1 : 0)
                .animation(active ? StatusPopoutMotion.fadeIn : StatusPopoutMotion.fadeOut, value: active)
                .allowsHitTesting(active)
                .accessibilityHidden(!active)
            }
        }
        .background(alignment: .topLeading) {
            if open {
                HoverTracker { popout.onPanelHover($0) }
                    .frame(width: bulge.width + 8, height: bulge.height)
                    .offset(x: edges.side == .right ? x : x - 8, y: bulge.minY)
            }
        }
        .mask(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: StatusPopoutLayout.cornerRadius)
                .frame(width: bulge.width, height: bulge.height)
                .offset(x: x, y: bulge.minY)
        }
    }
}

/// Hintergrund der Leiste in ihrer Form, in Bildproben durch eine feste
/// Flaeche ersetzt (Glas zeichnet ausserhalb des Bildschirms nur weiss).
private struct SidebarGlass<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.statusPopoutGlassStandIn) private var standIn
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellStyle) private var style

    func body(content: Content) -> some View {
        if standIn {
            content.background(colorScheme == .dark ? Color(white: 0.17) : Color(white: 0.95), in: shape)
        } else {
            let fill = style.paintsBar
                ? style.barFill
                : AnyShapeStyle(Color(nsColor: .windowBackgroundColor).opacity(GlassLook.fill))
            let blur = style.value(.barBlur) ?? 24
            let base = content
                .background(fill, in: shape)
                .background {
                    if style.paintsBar, !style.barIsOpaque, blur > 0 {
                        BackdropBlur(radius: blur).clipShape(shape)
                    }
                }
            if style.glass, !(style.paintsBar && style.barIsOpaque) {
                base.glassEffect(.clear, in: shape)
            } else {
                base
            }
        }
    }
}

/// Umriss der Leiste samt Beule: ein durchgehender Pfad, keine zwei
/// uebereinandergelegten Formen (die fuellt SwiftUI je nach Regel mit einem
/// Loch in der Ueberlappung).
///
/// Am Uebergang zur Beule zwei einwaertsgekruemmte Ecken, damit sie aus der
/// Leiste zu wachsen scheint statt angeklebt zu wirken.
struct SidebarGlassShape: Shape {
    var barWidth: CGFloat
    var bulge: CGRect
    /// Leiste rechts: der Umriss an der Mitte gespiegelt.
    var mirrored = false
    var radius: CGFloat = 0
    var inset: CGFloat = 0

    /// Lage und Groesse der Beule animieren: so gleitet die Form beim
    /// Oeffnen, Wechseln und Schliessen.
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
        let path = leftPath(in: rect)
        guard mirrored else { return path }
        return path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0))
    }

    private func leftPath(in rect: CGRect) -> Path {
        var path = Path()
        let rc = max(0, min(radius, barWidth / 2, rect.height / 2))
        let yb = rc > 0 ? rect.maxY - inset : rect.maxY
        guard bulge.width > 0.5, bulge.height > 0.5 else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + barWidth - rc, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.minX + barWidth, y: rect.minY + rc),
                              control: CGPoint(x: rect.minX + barWidth, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + barWidth, y: yb - rc))
            path.addQuadCurve(to: CGPoint(x: rect.minX + barWidth - rc, y: yb),
                              control: CGPoint(x: rect.minX + barWidth, y: yb))
            path.addLine(to: CGPoint(x: rect.minX, y: yb))
            path.closeSubpath()
            return path
        }
        let r = min(StatusPopoutLayout.cornerRadius, bulge.width / 2, bulge.height / 2)
        let x = rect.minX
        let edge = x + barWidth
        let top = max(rect.minY, bulge.minY)
        let bottom = min(rect.maxY, bulge.maxY)
        let right = edge + bulge.width
        let j = StatusPopoutJoin.radii(top: top, bottom: bottom, minY: rect.minY, maxY: rect.maxY,
                                       width: bulge.width, join: StatusPopoutLayout.join)

        let rt = min(rc, max(0, top - j.top - rect.minY))
        let rb = min(rc, max(0, yb - bottom - j.bottom))
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: edge - rt, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: edge, y: rect.minY + rt), control: CGPoint(x: edge, y: rect.minY))
        // Rechte Leistenkante hinunter bis zur Beule, dann einwaerts gekruemmt
        // hinein.
        path.addLine(to: CGPoint(x: edge, y: top - j.top))
        path.addQuadCurve(to: CGPoint(x: edge + j.top, y: top),
                          control: CGPoint(x: edge, y: top))
        path.addLine(to: CGPoint(x: right - r, y: top))
        path.addQuadCurve(to: CGPoint(x: right, y: top + r), control: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right, y: bottom - r))
        path.addQuadCurve(to: CGPoint(x: right - r, y: bottom), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: edge + j.bottom, y: bottom))
        path.addQuadCurve(to: CGPoint(x: edge, y: bottom + j.bottom), control: CGPoint(x: edge, y: bottom))
        // Weiter die Leistenkante hinunter und um die Leiste herum zurueck.
        path.addLine(to: CGPoint(x: edge, y: yb - rb))
        path.addQuadCurve(to: CGPoint(x: edge - rb, y: yb), control: CGPoint(x: edge, y: yb))
        path.addLine(to: CGPoint(x: x, y: yb))
        path.closeSubpath()
        return path
    }
}
