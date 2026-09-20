import SwiftUI

extension View {
    /// Liquid Glass behind a toast, lightly tinted on request.
    ///
    /// Here SwiftUI's `glassEffect` instead of an NSGlassEffectView like the
    /// edge windows use: there the glass is the whole window, here each
    /// toast has its own, and that has to move with opacity and size
    /// during fade in/out. An embedded AppKit glass does not reliably follow
    /// SwiftUI's transitions; the SwiftUI glass is the same
    /// material and belongs to the transition. Without GlassEffectContainer, so that
    /// neighboring toasts don't flow into each other.
    ///
    /// Own file so the screenshot test can swap it for a stand-in -
    /// glass draws only white when rendered offscreen.
    /// `enabled` false: no glass at all - a theme that turns off
    /// `--apollo-glass` gets a flat surface instead of material.
    func toastGlass(tint: Color?, cornerRadius: CGFloat, enabled: Bool = true) -> some View {
        Group {
            if enabled {
                glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
            } else {
                self
            }
        }
    }
}
