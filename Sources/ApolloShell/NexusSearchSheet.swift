import SwiftUI

/// Frame of a picker window with search: title (with an optional sentence
/// underneath), search field, divider, `content` (list or placeholder),
/// divider, cancel - as both `NexusBarAppPicker` (pick app) and
/// `UtilitiesShortcutPicker` (pick shortcut) need it. Always
/// 380x480, as both already were before the merge.
struct NexusSearchSheet<Content: View>: View {
    let title: LocalizedStringKey
    /// Extra sentence under the title; `nil` = none (pick app).
    let subtitle: LocalizedStringKey?
    let searchPrompt: LocalizedStringKey
    @Binding var query: String
    let onCancel: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            header
            NexusSearchField(prompt: searchPrompt, text: $query)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            Divider()
            content()
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
        }
        .frame(width: 380, height: 480)
    }

    @ViewBuilder private var header: some View {
        if let subtitle {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 10)
        } else {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 10)
        }
    }
}
