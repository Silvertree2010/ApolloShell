import SwiftUI

// Die Galerie hinter "Hinzufuegen": in der Leiste, im Utilities-Panel und im
// Dashboard dieselbe Umrahmung (Titel, Absatz, Raster in einem ScrollView,
// Abbrechen) um eine je eigene Kachel. Nur das Utilities-Panel gruppiert
// seine Kacheln nach Art (Schalter/Aktionen/Eigene) - dafuer bleibt der
// Inhalt der Umrahmung ein Platzhalter.

/// Rahmen einer Galerie-Seite: Titel, ein Satz Erklaerung, das Raster
/// (`content`) in einem ScrollView, unten Abbrechen. Fuer Leiste und
/// Dashboard `content` direkt ein `LazyVGrid`; das Utilities-Panel gruppiert
/// mehrere Raster mit eigenen Ueberschriften darin.
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
                Button("Abbrechen", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Eine Kachel der Galerie: Symbol, Name, eine Zeile Zusammenfassung, oben
/// rechts ein Hinweis (`badge`, z. B. "Schon da"; `nil` = keiner). Grau und
/// ohne Wirkung, wenn `available` falsch ist.
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
        // Nexus ist ein normales, aktives Fenster: hier reicht onHover.
        .onHover { hovering = $0 }
        .help(help)
    }
}
