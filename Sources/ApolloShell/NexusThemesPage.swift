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
                    Text("Themes are not available in this build.")
                        .foregroundStyle(.secondary)
                }
            }
            NexusSaveWarning(failed: store.saveFailed)
        }
        .alert("Import failed", isPresented: Binding(
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
            NexusThemeRow(title: String(localized: "No theme"),
                          subtitle: String(localized: "The colours of macOS, as without a file"),
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
            Text("Selected theme")
        } footer: {
            if themes.available.isEmpty {
                Text("No theme in the folder yet. Every .css file is one, and so is a folder with a theme.css in it – images may sit next to that one.")
            } else {
                Text("A change to the file takes effect at once, without a restart.")
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
                    Text("… and \(issues.count - 8) more")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Notes about the theme")
            } footer: {
                Text("Notes are not errors: whatever could not be read stays at its built-in value.")
            }
        }

        Section {
            Button("Add theme…") { importTheme(into: themes) }
            Button("Show folder in Finder") { themes.revealFolder() }
            Button("Read again") { themes.reload() }
        } header: {
            Text("Folder")
        } footer: {
            Text(verbatim: (themes.folder.path as NSString).abbreviatingWithTildeInPath)
                .textSelection(.enabled)
        }

        Section {
            Link("How a theme is put together",
                 destination: URL(string: "https://github.com/Silvertree2010/ApolloShell/blob/main/docs/THEMES.md")!)
        }
    }

    private func subtitle(for theme: Theme) -> String {
        var parts: [String] = []
        if !theme.author.isEmpty { parts.append(theme.author) }
        if !theme.details.isEmpty { parts.append(theme.details) }
        if !theme.issues.isEmpty { parts.append(String(localized: "\(theme.issues.count) note(s)")) }
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
        panel.prompt = String(localized: "Add")
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
                        .accessibilityLabel(Text("Selected"))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
