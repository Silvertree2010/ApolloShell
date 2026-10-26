import SwiftUI

enum GlassLook {
    static let fill: Double = 0.85
}

@Observable @MainActor
final class PanelInset {
    var e = EdgeInsets()
    /// Das Kantenfenster sitzt gespiegelt am linken Rand.
    var m = false
}

struct PanelRoot<C: View>: View {
    let r: CGFloat
    let ins: PanelInset
    let c: C

    var body: some View {
        c.environment(\.drawerMirrored, ins.m)
            .padding(ins.e)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(PanelGlass(r: r))
    }
}

private struct PanelGlass: ViewModifier {
    let r: CGFloat
    @Environment(\.statusPopoutGlassStandIn) private var standIn
    @Environment(\.colorScheme) private var cs
    @Environment(\.shellStyle) private var st

    func body(content: Content) -> some View {
        let sh = RoundedRectangle(cornerRadius: st.panelRadius(r))
        if standIn {
            content.background(cs == .dark ? Color(white: 0.17) : Color(white: 0.95), in: sh)
        } else {
            let f = st.paintsPanel
                ? AnyShapeStyle(st.panelFill.opacity(st.panelOpacity))
                : AnyShapeStyle(Color(nsColor: .windowBackgroundColor).opacity(GlassLook.fill))
            let b = content.background(f, in: sh)
            if st.glass {
                b.glassEffect(.regular, in: sh)
            } else {
                b
            }
        }
    }
}

private struct DrawerMirroredKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Kantenfenster am linken statt am rechten Rand (Leiste rechts).
    var drawerMirrored: Bool {
        get { self[DrawerMirroredKey.self] }
        set { self[DrawerMirroredKey.self] = newValue }
    }
}
