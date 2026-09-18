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
    /// Gemessene Groesse jedes Inhalts: so steht die Zielgroesse schon fest,
    /// bevor die Beule losgeht, und ein spaeter geladener Inhalt (Bluetooth
    /// liest erst nach dem Oeffnen) gleitet auf seine neue Hoehe.
    @State private var sizes: [StatusPopoutKind: CGSize] = [:]

    var body: some View {
        GeometryReader { geometry in
            let size = sizes[popout.shown] ?? CGSize(width: StatusPopoutContent.width(popout.shown), height: 200)
            let open = popout.isOpen
            let top = StatusPopoutPlacement.top(
                anchorY: popout.anchorY, height: size.height, containerHeight: geometry.size.height
            )
            // Geschlossen: Breite 0 auf Hoehe des Symbols, also nur Leiste.
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
                SidebarContent(settings: settings, context: context)
                    .frame(width: Sidebar.width)
                    .frame(maxHeight: .infinity)
                popoutContent(size: size, top: top, bulge: bulge, open: open)
            }
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

/// Hintergrund der Leiste in ihrer Form, in Bildproben durch eine feste
/// Flaeche ersetzt (Glas zeichnet ausserhalb des Bildschirms nur weiss).
///
/// Welcher Hintergrund, sagt Nexus > Leiste > Hintergrund; warum es die Wahl
/// gibt und was die einzelnen Eintraege sollen, steht bei `BarBackground`.
private struct SidebarGlass<S: Shape>: ViewModifier {
    let shape: S
    let background: BarBackground
    @Environment(\.statusPopoutGlassStandIn) private var standIn
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellStyle) private var style

    /// Fensterfarbe, halb deckend: zieht das Glas in Richtung Fensterfarbe,
    /// laesst es aber noch Glas sein. Ganz aufhalten kann eine Toenung das
    /// Umfaerben ohnehin nicht (siehe `BarBackground`) - dafuer ist
    /// `fixedGlass` da.
    private static var tint: Color { Color(nsColor: .windowBackgroundColor).opacity(0.7) }

    /// Mit Theme faerbt das Theme die Leiste: die Farbe (oder der Verlauf)
    /// aus `--apollo-bar-color` beziehungsweise `--apollo-bar-gradient`, mit
    /// `--apollo-bar-opacity`. Die Wahl in Nexus > Leiste bleibt darunter
    /// sichtbar, solange das Theme durchscheinen laesst und Glas erlaubt -
    /// sonst waere eine halb deckende Leiste eine Leiste vor dem Schreibtisch.
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
                // Reihenfolge: erst das Glas hinter den Inhalt, dann die
                // deckende Flaeche hinter das Glas. Das Glas hat damit
                // ueberall dieselbe Flaeche vor sich statt des Schreibtischs
                // und der Fenster, seine Anpassung hat also nichts mehr zum
                // Anpassen. `clear` statt `regular`, weil nur diese Fassung
                // laut Apple gar nicht anpasst; die deckende Flaeche ist die
                // Schicht, die `clear` dafuer braucht.
                content
                    .glassEffect(.clear, in: shape)
                    .background(Color(nsColor: .windowBackgroundColor), in: shape)
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
        // Rechte Leistenkante hinunter bis zur Beule, dann einwaerts gekruemmt
        // hinein.
        path.addLine(to: CGPoint(x: edge, y: top - j))
        path.addQuadCurve(to: CGPoint(x: edge + j, y: top),
                          control: CGPoint(x: edge, y: top))
        path.addLine(to: CGPoint(x: right - r, y: top))
        path.addQuadCurve(to: CGPoint(x: right, y: top + r), control: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right, y: bottom - r))
        path.addQuadCurve(to: CGPoint(x: right - r, y: bottom), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: edge + j, y: bottom))
        path.addQuadCurve(to: CGPoint(x: edge, y: bottom + j), control: CGPoint(x: edge, y: bottom))
        // Weiter die Leistenkante hinunter und um die Leiste herum zurueck.
        path.addLine(to: CGPoint(x: edge, y: rect.maxY))
        path.addLine(to: CGPoint(x: x, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
