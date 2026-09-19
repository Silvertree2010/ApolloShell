import SwiftUI

/// Rahmen eines Auswahl-Fensters mit Suche: Titel (mit optionalem Satz
/// darunter), Suchfeld, Trennlinie, `content` (Liste oder Platzhalter),
/// Trennlinie, Abbrechen - wie `NexusBarAppPicker` (App waehlen) und
/// `UtilitiesShortcutPicker` (Kurzbefehl waehlen) es beide brauchen. Immer
/// 380x480, wie beide es vor der Zusammenlegung schon waren.
struct NexusSearchSheet<Content: View>: View {
    let title: LocalizedStringKey
    /// Zusaetzlicher Satz unter dem Titel; `nil` = keiner (App waehlen).
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
