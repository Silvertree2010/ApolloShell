import SwiftUI

/// The scaled-down, live preview in Nexus > Bar: a slightly offset surface
/// standing in for the glass, a border, scaled to `scale`, no mouse. Header
/// (title "Preview") and footer (sample-data note) stay with the caller.
/// The dashboard and the control centre had their own preview here too
/// until Task 7 -
/// since then both are edited in the global edit mode, on the real panel.
///
/// `scale` affects `scaleEffect` and the border (`1 / scale`); `frameSize`
/// is the final outer size, kept separate in case a caller needs a
/// clamped-down value for the visible scale but the unclamped one for the
/// frame.
struct NexusScaledPreview<Content: View>: View {
    let scale: CGFloat
    let frameSize: CGSize
    let cornerRadius: CGFloat
    let accessibilityLabel: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(Color.primary.opacity(0.07))
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1 / scale)
            }
            .scaleEffect(scale, anchor: .top)
            .frame(width: frameSize.width, height: frameSize.height, alignment: .top)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }
}
