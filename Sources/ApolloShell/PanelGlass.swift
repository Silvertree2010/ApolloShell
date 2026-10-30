import AppKit
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

struct BackdropBlur: NSViewRepresentable {
    let radius: Double

    func makeNSView(context: Context) -> BlurView {
        let v = BlurView()
        v.blendingMode = .behindWindow
        v.state = .active
        v.material = .underWindowBackground
        return v
    }

    func updateNSView(_ v: BlurView, context: Context) {
        v.radius = radius
    }

    final class BlurView: NSVisualEffectView {
        var radius: Double = 24 {
            didSet { if radius != oldValue { apply() } }
        }

        override func layout() {
            super.layout()
            apply()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            guard let layer else { return }
            for l in BackdropBlur.layers(layer) where String(describing: type(of: l)).contains("Backdrop") {
                guard let fs = l.filters as? [NSObject] else { continue }
                for f in fs where (f.value(forKey: "name") as? String)?.hasPrefix("gaussianBlur") == true {
                    f.setValue(radius, forKey: "inputRadius")
                }
                l.filters = fs
            }
        }
    }

    fileprivate static func layers(_ l: CALayer) -> [CALayer] {
        [l] + (l.sublayers ?? []).flatMap(layers)
    }
}
