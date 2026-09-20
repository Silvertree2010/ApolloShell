import SwiftUI

// The gallery behind "Add": the bar, the utilities panel and the
// dashboard share the same frame (title, paragraph, grid in a ScrollView,
// Cancel) around a tile that's each their own. Only the utilities panel groups
// its tiles by kind (toggles/actions/custom) - for that the
// content of the frame stays a placeholder.

/// Frame of a gallery page: title, a sentence of explanation, the grid
/// (`content`) in a ScrollView, Cancel at the bottom. For the bar and
/// dashboard `content` is a `LazyVGrid` directly; the utilities panel groups
/// several grids with their own headings inside.
struct NexusGallerySheet<Content: View>: View {
    let title: String
    let subtitle: String
    let size: CGSize
    let onCancel: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            ScrollView {
                content()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// A tile of the gallery: symbol, name, one line of summary, at the top
/// right a hint (`badge`, e.g. "Already there"; `nil` = none). Grayed out and
/// without effect when `available` is false.
struct NexusGalleryTile<Icon: View>: View {
    let title: String
    let summary: String
    let badge: String?
    let minHeight: CGFloat
    let available: Bool
    let help: String
    let action: () -> Void
    @ViewBuilder var icon: () -> Icon
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    icon()
                    Spacer(minLength: 4)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(title)
                    .font(.headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(Color.primary.opacity(hovering && available ? 0.09 : 0.05),
                        in: .rect(cornerRadius: 12, style: .continuous))
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.45)
        // Nexus is a normal, active window: onHover is enough here.
        .onHover { hovering = $0 }
        .help(help)
    }
}
