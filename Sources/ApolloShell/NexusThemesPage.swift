import AppKit
import ApolloShellCore
import SwiftUI
import UniformTypeIdentifiers

/// Nexus > Themes: welches Theme gilt, was im Ordner liegt, was daran auffiel.
///
/// Gewaehlt wird sofort - die ganze Shell faerbt um, ohne Neustart. Der
/// Ordner wird beobachtet (`ThemeStore`), wer also eine .css speichert, sieht
/// das Ergebnis im selben Moment.
struct NexusThemesPage: View {
    @Bindable var store: ShellSettingsStore
    let themes: ThemeStore?
    @State private var importError: String?

    var body: some View {
        NexusPageForm(page: .themes) {
            if let themes {
                content(themes)
            } else {
                Section {
                    Text("Themes stehen in dieser Fassung nicht zur Verfügung.")
                        .foregroundStyle(.secondary)
                }
            }
            NexusSaveWarning(failed: store.saveFailed)
        }
        .alert("Import fehlgeschlagen", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    @ViewBuilder
    private func content(_ themes: ThemeStore) -> some View {
        Section {
            NexusThemeRow(title: String(localized: "Ohne Theme"),
                          subtitle: String(localized: "Die Farben von macOS, wie ohne Datei"),
                          selected: themes.selection == nil) {
                themes.select(nil)
            }
            ForEach(themes.available, id: \.identifier) { theme in
                NexusThemeRow(title: theme.title,
                              subtitle: subtitle(for: theme),
                              selected: themes.selection == theme.identifier) {
                    themes.select(theme.identifier)
                }
            }
        } header: {
            Text("Gewähltes Theme")
        } footer: {
            if themes.available.isEmpty {
                Text("Noch kein Theme im Ordner. Jede .css-Datei ist eins, ein Ordner mit theme.css auch – dann dürfen Bilder daneben liegen.")
            } else {
                Text("Eine Änderung an der Datei wirkt sofort, ohne Neustart.")
            }
        }

        if let issues = selectedIssues(themes), !issues.isEmpty {
            Section {
                ForEach(Array(issues.prefix(8).enumerated()), id: \.offset) { _, issue in
                    Text(issue)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if issues.count > 8 {
                    Text("… und \(issues.count - 8) weitere")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Hinweise zum Theme")
            } footer: {
                Text("Hinweise sind kein Fehler: Was nicht gelesen werden konnte, steht auf der eingebauten Vorgabe.")
            }
        }

        Section {
            Button("Theme hinzufügen …") { importTheme(into: themes) }
            Button("Ordner im Finder zeigen") { themes.revealFolder() }
            Button("Neu einlesen") { themes.reload() }
        } header: {
            Text("Ordner")
        } footer: {
            Text(verbatim: (themes.folder.path as NSString).abbreviatingWithTildeInPath)
                .textSelection(.enabled)
        }

        Section {
            Link("Wie ein Theme aufgebaut ist",
                 destination: URL(string: "https://github.com/Silvertree2010/ApolloShell/blob/main/docs/THEMES.md")!)
        }
    }

    private func subtitle(for theme: Theme) -> String {
        var parts: [String] = []
        if !theme.author.isEmpty { parts.append(theme.author) }
        if !theme.details.isEmpty { parts.append(theme.details) }
        if !theme.issues.isEmpty { parts.append(String(localized: "\(theme.issues.count) Hinweis(e)")) }
        return parts.joined(separator: " · ")
    }

    private func selectedIssues(_ themes: ThemeStore) -> [String]? {
        guard themes.selection != nil else { return nil }
        return themes.theme.issues.map(\.description)
    }

    private func importTheme(into themes: ThemeStore) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "css") ?? .plainText, .folder]
        panel.prompt = String(localized: "Hinzufügen")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try themes.importTheme(from: url)
        } catch {
            importError = error.localizedDescription
        }
    }
}

/// Eine Zeile der Theme-Liste: Name, Unterzeile, Haken beim gewaehlten.
private struct NexusThemeRow: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityLabel(Text("Gewählt"))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
